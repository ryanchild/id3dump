#!/usr/bin/tclsh

if {$argc != 1} { 
  puts "usage: $argv0 filename"
  exit 1
}

if {[catch {set fd [open [lindex $argv 0]]} err]} {
  puts "an error occurred"
  exit 1
}

set colwidths [list 20 5]
set sep +
foreach w $colwidths {
  append sep -[string repeat - $w]-+
}
set fmt "| %-[lindex $colwidths 0]s | %-[lindex $colwidths 1]s |"

puts $sep
puts [format $fmt "Field" "Value"]
puts $sep

binary scan [read $fd 3] "A3" id3_identifier 
puts [format $fmt "ID3 Identifier" $id3_identifier]
binary scan [read $fd 2] "s" major_version 
puts [format $fmt "Major Version" $major_version]
puts $sep
