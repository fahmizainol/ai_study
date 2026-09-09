# Time the Ruby search board (portable_ai/search.rb) on the test suite's search
# position, under whatever Ruby runs this file. RGSS Ruby 1.8 figures are in the notes.
#   ruby _AI-Study/tools/search_bench.rb
root = File.expand_path(File.join(File.dirname(__FILE__), ".."))
$LOAD_PATH.unshift(root)
require "test/unit"
Test::Unit::AutoRunner.need_auto_run = false
load File.join(root, "tests", "test_portable_ai.rb")

t = PortableAITest.new("test_search_planner_declines_what_it_cannot_see")
actions = [t.move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 }),
           t.move(1, "ROCKSLIDE", 0, 100, 75, { "accuracy" => 90 }),
           t.move(2, "PROTECT", 0, 0, 0, {})]
snap = t.search_snap(actions)
board = PortableAI::Search.opening_board(snap, PortableAI::Model.config({}))
own = snap["actors"][0]["actions"]
foe = PortableAI::Search.foe_options(snap, board)

def clock(n)
  s = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  n.times { yield }
  (Process.clock_gettime(Process::CLOCK_MONOTONIC) - s) * 1000.0 / n
end

puts "#{RUBY_VERSION}  own options #{own.length}, foe options #{foe.length}"
puts format("board copy (Model.copy_hash x3, as resolve_switches does): %.4f ms",
            clock(20000) { o = PortableAI::Model.copy_hash(board); o["own_hps"] = PortableAI::Model.copy_hash(board["own_hps"]); o["foe_hps"] = PortableAI::Model.copy_hash(board["foe_hps"]) })
puts format("one board turn (outcomes, own[0] vs foe[0], with roll branches): %.4f ms",
            clock(5000) { PortableAI::Search.outcomes(snap, board, own[0], foe[0], true) })
puts format("leaf evaluation: %.4f ms", clock(20000) { PortableAI::Search.leaf(snap, board) })
[1, 2].each do |d|
  ms = clock(50) { PortableAI::Search.plan(snap, { "search_depth" => d, "search_foe_mix" => 0 }, Random.new(7)) }
  puts format("maximin depth %d, whole decision: %.2f ms", d, ms)
end
[1000, 5000].each do |it|
  ms = clock(5) { PortableAI::Search.plan(snap, { "search_mcts" => true, "search_iterations" => it }, Random.new(7)) }
  puts format("MCTS %d iterations, whole decision: %.1f ms  (%.4f ms per iteration)", it, ms, ms / it)
end
