# Engine-independent readers over the party x party damage matrix.
# Requires model.rb and effects.rb to have been loaded first; requires nothing from
# core.rb, which is the point -- both the rule planner (core.rb) and the search
# planner (search.rb) read the board through these and neither owns them.
#
# Everything here is a pure function of the snapshot. No config, no rng, no scoring.

module PortableAI
  # Beyond this many hits the exchange is not a race any more, it is a stall war, and
  # the counts stop carrying information. Cap rather than let a chip move produce a
  # 40-turn "plan" that compares equal to another one.
  RACE_MAX_HITS = 8

  # nil when nothing gets through, otherwise the capped number of hits.
  def self.hits_needed(hp, per_hit)
    return nil if per_hit.nil? || per_hit <= 0
    count = (hp / per_hit.to_f).ceil
    count = RACE_MAX_HITS if count > RACE_MAX_HITS
    count = 1 if count < 1
    count
  end

  # ---------------------------------------------------------------------------
  # 0.6.5. THE PARTY x PARTY DAMAGE MATRIX -- a pure derived layer over one new
  # snapshot field.
  #
  # Every rule above this line scores against the ACTIVE foe. That is the whole
  # board a move sees, but it is not the whole board a switch decides: sending the
  # only body that beats their Azumarill into a Scizor that removes it is a game
  # thrown away three turns before anything looks wrong, and a boost is worth what
  # it flips across the rest of the party, not a flat 55.
  #
  # The adapter builds `snapshot["matrix"]` -- one damage estimate per party pair,
  # both directions, cached and re-rolled only when a signature changes. This
  # section reads it and nothing else, so every consumer goes inert the instant the
  # field is absent: an adapter that exports no matrix (Reborn) is unchanged, which
  # is what makes its gauntlet the control for this version.
  #
  # SLOTS, NOT SEATS. A benched body has no seat, and a seat is not a party index.
  # The side tables carry both, and matrix_slot is the only way across.
  #
  # NOT in the cells, on purpose: HP (this layer derives the hit counts from the
  # side tables' current hp_pct, so a verdict decays as a body is chipped),
  # Intimidate, the Choice lock, entry hazards, and PRIORITY -- a cell is a damage
  # number, and damage_race is the thing that orders the final hit, so a body that
  # wins on Bullet Punch reads here as losing. The 0.6.4 switch estimators
  # still carry those and still feed candidate_race; the matrix is the wide, thin
  # view, not a replacement for the narrow, thick one. Defender-side screens ARE in
  # the numbers, because the engine's own damage estimate reads them.

  # Both sides needing six or more hits is not a race, it is a stall: at that depth
  # the exchange is decided by crits, status and residual, none of which these cells
  # carry. Deliberately below RACE_MAX_HITS (8), which is a CAP -- "both at the cap"
  # would need <= 12.5% a hit on both sides and would almost never be reachable --
  # and above WALL_BREAK_MAX_HITS (4), which asks the opposite question. The verdict
  # is recomputed from current HP every snapshot, so an S decays into W or L as soon
  # as one side is chipped enough to matter.
  MATRIX_STALL_HITS = 6

  def self.matrix(snapshot)
    m = (snapshot || {})["matrix"]
    m.is_a?(Hash) ? m : nil
  end

  # Seat (a battler index: actor["index"], target["index"], never an action's slot)
  # to party slot. nil for a seat no live party entry occupies.
  def self.matrix_slot(side_table, seat)
    return nil if side_table.nil? || seat.nil?
    side_table.each do |entry|
      next if entry.nil?
      return entry["slot"] if !entry["index"].nil? && entry["index"] == seat
    end
    nil
  end

  def self.matrix_entry(side_table, slot)
    return nil if side_table.nil? || slot.nil?
    side_table.each do |entry|
      next if entry.nil?
      return entry if entry["slot"] == slot
    end
    nil
  end

  def self.matrix_cell(snapshot, own_slot, foe_slot)
    m = matrix(snapshot)
    return nil if m.nil? || own_slot.nil? || foe_slot.nil?
    cells = m["cells"]
    return nil if !cells.is_a?(Hash)
    cell = cells["#{own_slot}:#{foe_slot}"]
    cell.is_a?(Hash) ? cell : nil
  end

  # Hits each way at the HP both bodies are actually standing on. nil on either side
  # means nothing that body has gets through, which is a distinct answer from "it
  # needs many hits" and the verdict below reads it as such.
  def self.matrix_hits(cell, own_hp, foe_hp)
    return nil if cell.nil?
    { "mine" => hits_needed(foe_hp, Model.number(cell["out"], 0.0)),
      "theirs" => hits_needed(own_hp, Model.number(cell["in"], 0.0)) }
  end

  # "W" this body wins the pair, "L" it loses, "S" neither finishes, nil unknown.
  #
  # No free-hit convention here. The turn a switch costs belongs to candidate_race
  # (:1210), which already charges it; a matrix verdict is the standing question
  # "who beats whom", asked of two bodies at their current HP.
  def self.matrix_verdict(snapshot, own_slot, foe_slot)
    cell = matrix_cell(snapshot, own_slot, foe_slot)
    return nil if cell.nil?
    m = matrix(snapshot)
    own = matrix_entry(m["own"], own_slot)
    foe = matrix_entry(m["foe"], foe_slot)
    return nil if own.nil? || foe.nil?
    cell_verdict(cell, Model.number(own["hp_pct"], 100.0),
                 Model.number(foe["hp_pct"], 100.0))
  end

  # The same judgement on a cell the caller is holding -- a transformed one, which by
  # construction is in no matrix (Core.setup_matrix_value).
  # A pair the engine could not price reads here exactly like a pair nothing lands in:
  # `out` nil and `out` 0.0 both give no hits and both lose. The distinction is kept in
  # the cell for the readout (`?` against `0%`) rather than acted on, because the
  # alternative -- a verdict of nil -- would silently drop the pair out of
  # matrix_answers and turn "we could not measure it" into "nothing answers it".
  def self.cell_verdict(cell, own_hp, foe_hp)
    return nil if cell.nil?
    return nil if own_hp <= 0 || foe_hp <= 0
    hits = matrix_hits(cell, own_hp, foe_hp)
    mine = hits["mine"]
    theirs = hits["theirs"]
    stalled_mine = mine.nil? || mine >= MATRIX_STALL_HITS
    stalled_theirs = theirs.nil? || theirs >= MATRIX_STALL_HITS
    return "S" if stalled_mine && stalled_theirs
    return "L" if mine.nil?
    return "W" if theirs.nil?
    return "W" if mine < theirs
    return "L" if mine > theirs
    faster = cell["faster"]
    return nil if faster != true && faster != false
    faster ? "W" : "L"
  end

  def self.matrix_live_slots(side_table)
    out = []
    (side_table || []).each do |entry|
      next if entry.nil?
      next if entry["alive"] == false
      next if Model.number(entry["hp_pct"], 0.0) <= 0
      out << entry["slot"]
    end
    out
  end

  # Every live body on our side that beats this foe.
  def self.matrix_answers(snapshot, foe_slot)
    m = matrix(snapshot)
    return [] if m.nil?
    matrix_live_slots(m["own"]).select do |own_slot|
      matrix_verdict(snapshot, own_slot, foe_slot) == "W"
    end
  end

  # The live foes this body is the ONLY answer to. Empty when the matrix is absent,
  # so a consumer written against it is inert by construction.
  def self.sole_answers(snapshot, own_slot)
    m = matrix(snapshot)
    return [] if m.nil? || own_slot.nil?
    matrix_live_slots(m["foe"]).select do |foe_slot|
      answers = matrix_answers(snapshot, foe_slot)
      answers.length == 1 && answers[0] == own_slot
    end
  end

  # A cell as it would read after the actor's own stat stages. Physical output scales
  # with Attack, special with Special Attack, and the mirror on the way in; speed
  # stages can flip who moves first, which is the whole point of a Dragon Dance.
  # Ratios, not the engine's numerator/denominator pairs -- STAGE_MULT.
  #
  # Applied from stage 0. Its only caller is the first-setup arm (repeats == 0, which
  # setup_stage keys off positive_stage_total < 2), so the body is carrying at most
  # one stage already and the error is bounded by one.
  def self.matrix_transform_cell(cell, stages, own_speed, foe_speed, trick_room)
    return nil if cell.nil?
    out = Model.copy_hash(cell)
    stages = stages || {}
    offence = (cell["out_cat"] == "special") ? stages["spa"] : stages["atk"]
    defence = (cell["in_cat"] == "special") ? stages["spd"] : stages["def"]
    if !cell["out"].nil? && !offence.nil? && offence != 0
      out["out"] = Model.number(cell["out"], 0.0) * Effects.stage_multiplier(offence)
    end
    if !cell["in"].nil? && !defence.nil? && defence != 0
      out["in"] = Model.number(cell["in"], 0.0) / Effects.stage_multiplier(defence)
    end
    speed_stage = stages["speed"]
    if !speed_stage.nil? && speed_stage != 0 && !own_speed.nil? && !foe_speed.nil?
      mine = own_speed.to_f * Effects.stage_multiplier(speed_stage)
      # The adapters' own convention (faster_than_foes?): strictly greater is faster,
      # a tie is not, and Trick Room inverts it.
      out["faster"] = trick_room ? mine < foe_speed.to_f : mine > foe_speed.to_f
    end
    out
  end
end
