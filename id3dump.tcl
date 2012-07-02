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

proc InitTable {} {
  global gTableSep gTableFmt gTableWidth
  set colWidths {30 30}
  set gTableWidth 5 ;# margins
  foreach w $colWidths {
    incr gTableWidth $w
  }
  if {![info exists gTableSep]} {
    set gTableSep +
    foreach w $colWidths {
      append gTableSep -[string repeat - $w]-+
    }
  }
  if {![info exists gTableFmt]} {
    set gTableFmt "| %-[lindex $colWidths 0]s | %-[lindex $colWidths 1]s |"
  }
}

proc PrintTableHeader {title} {
  global gTableWidth gTableSep gTableFmt
  puts +[string repeat - $gTableWidth]+
  set diff [expr $gTableWidth - [string length $title]]
  set padLeft [expr $diff / 2]
  set padRight [expr $padLeft + [expr $diff % 2]]
  set title [string repeat " " $padLeft]$title[string repeat " " $padRight]
  puts |$title|
  puts $gTableSep
  puts [format $gTableFmt "Field" "Value"]
  puts $gTableSep
}

proc PrintTableFooter {} {
  global gTableSep
  puts $gTableSep\n
}

proc PrintTableRow {field value} {
  global gTableFmt
  puts [format $gTableFmt $field $value]
}

proc PrintTable {title rows} {
  PrintTableHeader $title
  foreach r $rows {
    PrintTableRow [lindex $r 0] [lindex $r 1]
  }
  PrintTableFooter
}

proc ErrNotID3 {} {
  global argv
  puts "File [lindex $argv 0] does not contain an ID3 tag"
  exit 1
}

proc ReadID3Data {fd bytes} {
  global gBytesRead gID3Size
  if {![info exists gBytesRead]} {
    set gBytesRead 0
  }
  if {[info exists gID3Size] && $gBytesRead >= $gID3Size - 10} {
    return 0
  }
  incr gBytesRead $bytes
  read $fd $bytes
}

proc ReadFrame {fd id3frame} {
  upvar $id3frame f
  set data [ReadID3Data $fd 4]
  if {$data == 0} {
    return 0
  }
  binary scan $data A* frameid
  lappend f [list "Frame ID" $frameid]
  binary scan [ReadID3Data $fd 4] I size
  lappend f [list "Size" $size]
  binary scan [ReadID3Data $fd 2] S flags
  ReadID3Data $fd $size
  lappend f [list "Data" "<binary data>"]
  return 1
}

if {$argc != 1} { 
  puts stderr "usage: $argv0 filename"
  exit 1
}

if {[catch {set fd [open [lindex $argv 0]]} err]} {
  puts stderr $err
  exit 1
}
fconfigure $fd -translation binary

InitTable

# read file identifier
binary scan [ReadID3Data $fd 3] A3 val 
if {$val ne "ID3"} {ErrNotID3}
lappend id3header [list "File identifier" $val]

# read version info
binary scan [ReadID3Data $fd 1] c major 
binary scan [ReadID3Data $fd 1] c rev
lappend id3header [list "Version" ${major}.${rev}]
# read header flags
binary scan [ReadID3Data $fd 1] c flags
lappend id3header [list "Unsynchronization" [expr $flags & 0x80]]
set extendedHeader [expr $flags & 0x40]
lappend id3header [list "Extended header" $extendedHeader]
lappend id3header [list "Experimental indicator" [expr $flags & 0x20]]

# get ID3 tag size
set bitstring "0000"
for {set i 0} {$i < 4} {incr i} {
  binary scan [ReadID3Data $fd 1] B* tmp
  if {[string index $tmp 0] ne "0"} {ErrNotID3}
  append bitstring [string range $tmp 1 end]
}
binary scan [binary format B* $bitstring] I gID3Size
lappend id3header [list "Size" $gID3Size]

# if there is an extended header, read it
if {$extendedHeader} {
  binary scan [ReadID3Data $fd 4] I val
  lappend extheader [list "Extended header size" $val]
  binary scan [ReadID3Data $fd 2] S val
  lappend extheader [list "Extended flags" [expr $val & 0x8000]]
  binary scan [ReadID3Data $fd 4] I val
  lappend extheader [list "Size of padding" $val]
}

PrintTable "ID3 Header" $id3header
set i 1
while {[ReadFrame $fd id3frame$i]} {
  PrintTable "Frame #$i" [set id3frame$i]
  incr i
}
