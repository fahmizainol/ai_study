# Keep all existing message data intact; only add this item's three strings.
class OrderedHash
  def self._load(raw)
    new(raw)
  end
  def initialize(raw)
    @raw = raw
  end
  def _dump(depth = -1)
    @raw
  end
  def ==(other)
    other.is_a?(OrderedHash) && @raw == other.instance_variable_get(:@raw)
  end
end
original = Marshal.load(File.binread(ARGV[0]))
updated = Marshal.load(Marshal.dump(original))
{7 => "Heavy-Duty Boots", 8 => "Heavy-Duty Boots",
 9 => "Protects the holder from entry hazards when switching into battle."}.each do |table, text|
  raise "Unexpected message table" unless updated[table].is_a?(Array)
  old = updated[table][743]
  raise "Item message slot 743 is occupied" unless old.nil? || old == text
  updated[table][743] = text
end
check = Marshal.load(Marshal.dump(updated))
check.each_with_index do |table, i|
  next if [7, 8, 9].include?(i)
  raise "Unrelated messages changed" unless table == original[i]
end
[7, 8, 9].each do |i|
  raise "Existing item messages changed" unless check[i][0...743] == original[i][0...743]
end
File.binwrite(ARGV[1], Marshal.dump(updated))
