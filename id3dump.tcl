#!/usr/bin/tclsh
#
# Copyright 2012 Ryan Child
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

proc PrintTags {arrlist} {
  array set arr $arrlist
  set colwidths [list 20 5]
  set sep +
  foreach w $colwidths {
    append sep -[string repeat - $w]-+
  }
  set fmt "| %-[lindex $colwidths 0]s | %-[lindex $colwidths 1]s |"
  puts $sep
  puts [format $fmt "Field" "Value"]
  puts $sep
  foreach name [array names arr] {
    puts [format $fmt $name $arr($name)]
  }
  puts $sep
}

if {$argc != 1} { 
  puts "usage: $argv0 filename"
  exit 1
}

if {[catch {set fd [open [lindex $argv 0]]} err]} {
  puts "an error occurred"
  exit 1
}

binary scan [read $fd 3] "A3" val 
set {values(ID3 Identifier)} $val
binary scan [read $fd 2] "s" val 
set {values(Major Version)} $val
PrintTags [array get values]

