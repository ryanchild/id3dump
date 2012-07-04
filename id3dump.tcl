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

proc shift {lst count} {
  upvar $lst l
  upvar $count c
  set l [lreplace $l 0 0]
  incr c -1
}

proc UsageString {} {
  global argv0
  # keep synced with ParseArgs
  set optionalArgs [list --verbose --dump-cover]
  set str "usage: $argv0 \[[join $optionalArgs "\] \["]\] file"
  return $str
}

proc ParseArgs {} {
  global argv gSettings
  foreach arg $argv {
    switch -exact -- $arg {
      --verbose {
        set gSettings(verbose) 1
        shift argv argc
      }
      --dump-cover { 
        set gSettings(dump_cover) 1
        shift argv argc
      }
      default {
        if {[string range $arg 0 0] eq "-"} {
          error "unrecognized argument: $arg"
        } else {
          set gSettings(fname) $arg
        }
        shift argv argc
        break
      }
    }
  }
  if {[llength $argv]} {
    error "too many arguments"
  }
}

proc GetSetting {s} {
  global gSettings
  if {[info exists gSettings($s)]} {
    return $gSettings($s)
  } else {
    return 0
  }
}

proc ID3_Size_From_Int {s} {
  binary scan [binary format I $s] B32 bitstring
  regexp .{4}(.{7})(.{7})(.{7})(.{7}) $bitstring m one two three four
  binary format B32 "0${one}0${two}0${three}0${four}"
}

proc ID3_Size_To_Int {s} {
  binary scan $s B32 bitstring
  regexp .(.{7}).(.{7}).(.{7}).(.{7}) $bitstring m one two three four
  binary scan [binary format B32 "0000${one}${two}${three}${four}"] I ret
  return $ret
}

proc ID3_Read_Header {fd} {
  global gID3Data
  set data [read $fd 10]

  binary scan $data A3 ident 
  binary scan $data @5c flags
  binary scan $data @6I size
  if {$ident ne "ID3" || $size & 0x80808080} {
    error "valid ID3 header not found"
  }

  set extendedHeader [expr $flags & 0x40]
  if {$extendedHeader} {
    set gID3Data($fd,extendedheader) [read $fd 10]
    incr gID3Data($fd,size) 10
  }

  set sizebytes [string range $data end-3 end]
  set gID3Data($fd,sizeInHeader) [ID3_Size_To_Int $sizebytes]
  set gID3Data($fd,header) $data
}

proc ID3_Open {fname} {
  global gID3Data 
  set fd [open $fname]
  fconfigure $fd -translation binary
  set gID3Data($fd,currHandle) 0
  set gID3Data($fd,size) 0

  if {[catch {ID3_Read_Header $fd}]} {
    error "valid ID3 header not found in \"$fname\""
  }
  while {$gID3Data($fd,size) < $gID3Data($fd,sizeInHeader)} {
    binary scan [read $fd 4] A* id
    binary scan [read $fd 4] I size
    binary scan [read $fd 2] S flags
    set data [read $fd $size]

    set gID3Data($fd,$gID3Data($fd,currHandle),id) $id
    set gID3Data($fd,$gID3Data($fd,currHandle),size) $size
    set gID3Data($fd,$gID3Data($fd,currHandle),flags) $flags
    set gID3Data($fd,$gID3Data($fd,currHandle),data) $data
    set gID3Data($fd,h$id) $gID3Data($fd,currHandle)
    incr gID3Data($fd,size) [expr $size + 10] ;# we also read the header
    incr gID3Data($fd,currHandle)
    lappend gID3Data($fd,frames) $id

    if {[GetSetting verbose]} {
      puts "Read $id frame: $size bytes"
    }
  }
  if {[GetSetting verbose]} {
    puts "ID3 Size: $gID3Data($fd,sizeInHeader) \
          (read $gID3Data($fd,size) bytes)\n"
  }
  return $fd
}

proc ID3_Close {fd} {
  global gID3Data
  for {set i 0} {$i < $gID3Data($fd,currHandle)} {incr i} {
    if {[info exists gID3Data($fd,h$gID3Data($fd,$i,id))]} {
      unset gID3Data($fd,h$gID3Data($fd,$i,id))
    }
    unset gID3Data($fd,$i,id)
    unset gID3Data($fd,$i,size)
    unset gID3Data($fd,$i,flags)
    unset gID3Data($fd,$i,data)
  }
  unset gID3Data($fd,size)
  unset gID3Data($fd,sizeInHeader)
  unset gID3Data($fd,currHandle)
  unset gID3Data($fd,header)
  unset gID3Data($fd,frames)
  close $fd
}

proc ID3_Write_Frame {fd h} {
  global gID3Data
  puts $fd [binary format a4 $gID3Data($h,id)]
  puts $fd [binary format I $gID3Data($h,size)]
  puts $fd [binary format S $gID3Data($h,flags)]
  puts $fd $gID3Data($h,data)
}

proc ID3_Num_Frames {fd} {
  global gID3Data
  return $gID3Data($fd,currHandle)
}

proc ID3_Write_Frames {fd} {
  global gID3Data
  for {set i 0} {$i < [ID3_Num_Frames $fd]} {incr i} {
    ID3_Frame_Write $fd $i
  }
}

proc ID3_Get_Data {fd frameid} {
  global gID3Data
  set handle $gID3Data($fd,h$frameid)
  return $gID3Data($fd,$handle,data)
}

proc ID3_Get_Frames {id} {
  global gID3Data
  return $gID3Data($id,frames)
}

proc ID3_Have_Frame {fd frameid} {
  global gID3Data
  return [info exists gID3Data($fd,h$frameid)]
}

proc ID3_Get_Text {fd frameid} {
  if {[string range $frameid 0 0] ne "T"} {
    error "only able to get text values from frame IDs that start with 'T'"
  }
  binary scan [ID3_Get_Data $fd $frameid] A* txt
  return [string range $txt 1 end] ;# skip text encoding byte
}

proc ID3_Print_Header {fd} {
  global gID3Data
  upvar 0 $gID3Data($fd,header) data

  binary scan $data @3c major 
  binary scan $data @4c rev
  binary scan $headerData @5c flags
  set unsync [expr $flags & 0x80]]
  set extendedHeader [expr $flags & 0x40]
  set experimental [expr $flags & 0x20]
  set size [ID3_Size_To_Int [string range $data end-4 end]]
}

proc ID3_Dump_Artwork {fd} {
  set data [ID3_Get_Data $fd APIC]

  set idx 1
  set mime [lindex [split [string range $data $idx end] \x00] 0]
  incr idx [expr [string length $mime] + 1]
  set desc [lindex [split [string range $data  $idx end] \x00] 0]
  incr idx [expr [string length $desc] + 1]

  set fname cover.[string range $mime [expr [string first / $mime] + 1] end]
  set out [open $fname w]
  fconfigure $out -translation binary -encoding binary
  puts $out [string range $data $idx end]
  close $out
}

proc InitTable {} {
  global gTableSep gTableFmt gTableWidth
  set colWidths {50 30}
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

proc PrintTableHeader {title {header {Field Value}}} {
  global gTableWidth gTableSep gTableFmt
  puts +[string repeat - $gTableWidth]+
  set diff [expr $gTableWidth - [string length $title]]
  set padLeft [expr $diff / 2]
  set padRight [expr $padLeft + [expr $diff % 2]]
  set title [string repeat " " $padLeft]$title[string repeat " " $padRight]
  puts |$title|
  puts $gTableSep
  puts [format $gTableFmt [lindex $header 0] [lindex $header 1]]
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

proc PrintTable {title rows {header {Field Value}}} {
  PrintTableHeader $title $header
  foreach r $rows {
    PrintTableRow [lindex $r 0] [lindex $r 1]
  }
  PrintTableFooter
}

if {[catch {ParseArgs} err]} {
  puts stderr $err
  puts stderr [UsageString]
  exit 1
}

if {[catch {set id3 [ID3_Open [GetSetting fname]]} err]} {
  puts stderr $err
  exit 1
}

set scriptdir [file dirname [info script]]
source [file join $scriptdir frameids.tcl]
source [file join $scriptdir genres.tcl]

InitTable

foreach fid [ID3_Get_Frames $id3] {
  if {[info exists frameids($fid)]} {
    set txt [ID3_Get_Text $id3 $fid]
    if {$fid eq "TCON"} {
      catch {
        set txt $genres([lindex [regexp -inline {\((\d\d)\)} $txt] 1])
      }
    }
    lappend tbl [list "$fid ($frameids($fid))" $txt]
  } 
}

PrintTable "ID3 Text Information Frames" $tbl {"Frame" "Value"}

if {[GetSetting dump_cover]} {
  ID3_Dump_Artwork $id3
}

ID3_Close $id3
