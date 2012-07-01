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
  set colwidths [list 30 10]
  set sep +
  foreach w $colwidths {
    append sep -[string repeat - $w]-+
  }
  set fmt "| %-[lindex $colwidths 0]s | %-[lindex $colwidths 1]s |"
  puts $sep
  puts [format $fmt "Field" "Value"]
  puts $sep
  foreach name [lsort [array names arr]] {
    puts [format $fmt $name $arr($name)]
  }
  puts $sep
}

proc ErrNotID3 {} {
  global argv
  puts "File [lindex $argv 0] does not contain an ID3 tag"
  exit 1
}

if {$argc != 1} { 
  puts "usage: $argv0 filename"
  exit 1
}

if {[catch {set fd [open [lindex $argv 0]]} err]} {
  puts "an error occurred"
  exit 1
}

binary scan [read $fd 3] A3 val 
if {$val ne "ID3"} {ErrNotID3}

set {values(File identifier)} $val
binary scan [read $fd 1] c val 
set {values(Major version)} $val
binary scan [read $fd 1] c val
set {values(Revision number)} $val
binary scan [read $fd 1] c val
set {values(Unsynchronisation)} [expr $val & 0x80]
set {values(Extended header)} [expr $val & 0x40]
set {values(Experimental indicator)} [expr $val & 0x20]

# get ID3 tag size
set bitstring "0000"
set i 0
while {$i < 4} {
  binary scan [read $fd 1] B* tmp
  if {[string index $tmp 0] ne "0"} {ErrNotID3}
  append bitstring [string range $tmp 2 end]
  incr i
}
binary scan [binary format B* $bitstring] I size
set values(Size) $size

# if there is an extended header, read it
if {$values(Extended header)} {
  binary scan [read $fd 4] I val
  set {values(Extended header size)} $val
  binary scan [read $fd 2] S val
  set {values(Extended flags)} [expr $val & 0x8000]
  binary scan [read $fd 4] I val
  set {values(Size of padding)} $val
}

PrintTags [array get values]
