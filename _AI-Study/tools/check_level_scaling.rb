MAXLEVEL = 100
LEASH = 6

def pbBalancedLevel(levels)
  return 1 if levels.length==0
  sum=0; levels.each{|l| sum+=l}
  return 1 if sum==0
  average=sum.to_f/levels.length.to_f
  v=0; levels.each{|l| d=l-average; v+=d*d}
  stdev=Math.sqrt(v/levels.length)
  weights=[]
  levels.each do |l|
    w=l.to_f/sum.to_f
    if w<0.5 then w-=(stdev/MAXLEVEL.to_f); w=0.001 if w<=0.001
    else w+=(stdev/MAXLEVEL.to_f); w=0.999 if w>=0.999 end
    weights.push(w)
  end
  ws=0; weights.each{|w| ws+=w}
  mean=0
  for i in 0...levels.length; mean+=levels[i]*weights[i]; end
  mean/=ws; mean=mean.round; mean=1 if mean<1; mean+=2
  mean=MAXLEVEL if mean>MAXLEVEL
  mean
end

# A = balanceo = pbBalancedLevel(party) - 1
def scale(team_levels, player_levels, leash=LEASH)
  a = pbBalancedLevel(player_levels) - 1
  ace = team_levels.max
  team_levels.map do |l|
    n = a + (l - ace)
    n = l if n < l
    n = l + leash if n > l + leash
    n = 1 if n < 1
    n = MAXLEVEL if n > MAXLEVEL
    n
  end
end

def show(label, team, player)
  a = pbBalancedLevel(player) - 1
  printf("%-34s player=%-22s A=%-3d %s -> %s\n", label, player.inspect, a,
         team.inspect, scale(team, player).inspect)
end

puts "== gym 4 (designed ace 36, expert cap 36) -- PRESSURE ONLY =="
show("on curve",            [35,35,35,35,35,36], [36,35,35,34,34,33])
show("slightly behind",     [35,35,35,35,35,36], [33,32,32,31,31,30])
show("far behind",          [35,35,35,35,35,36], [24,23,22,22,21,20])
show("over-levelled (cap off)",[35,35,35,35,35,36], [50,50,49,48,48,47])
puts
puts "== route 1 filler (designed 3) vs an 8-badge player =="
show("backtrack",           [3,3], [57,56,56,55,55,54])
puts
puts "== raising a baby drags the anchor =="
show("with lv-12 in party",  [35,35,35,35,35,36], [34,34,33,30,28,12])
show("without it",           [35,35,35,35,35,36], [34,34,33,30,28])
puts
puts "== the developer's hand-scaled balanceo fights =="
[[[0,0],"all balanceo"],[[1,1,1],"all balanceo+1"],[[-2,-2],"all balanceo-2"],
 [[0,-2],"mixed 0/-2"],[[0,0,-2,-2],"mixed"]].each do |offs,name|
  [[5,5,5],[30,28,27,26],[60,59,58,57,55,50]].each do |player|
    bal = pbBalancedLevel(player) - 1
    team = offs.map{|o| bal + o}
    out  = scale(team, player)
    delta = out[0] - team[0]
    ok = (offs.max >= 0) ? (out == team) : (delta == -offs.max + 0)
    printf("  %-16s player_bal=%-3d team=%-18s -> %-18s %s\n", name, bal,
           team.inspect, out.inspect,
           out == team ? "unchanged" : "rises +#{delta}")
  end
end
