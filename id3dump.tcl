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

proc Usage_String {} {
  global argv0
  # keep synced with Parse_Args
  set optionalArgs [list --verbose --dump-cover]
  set str "usage: $argv0 \[[join $optionalArgs "\] \["]\] file"
  return $str
}

proc Parse_Args {} {
  global argc argv gSettings
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

proc Get_Setting {s} {
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

proc ID3_Add_Frame {fd id header data} {
  global gID3Data

  set gID3Data($fd,$gID3Data($fd,currHandle),id) $id
  set gID3Data($fd,$gID3Data($fd,currHandle),header) $header
  set gID3Data($fd,$gID3Data($fd,currHandle),data) $data
  set gID3Data($fd,h$id) $gID3Data($fd,currHandle)

  incr gID3Data($fd,size) [string length $header]
  incr gID3Data($fd,size) [string length $data]
  incr gID3Data($fd,currHandle)
}

proc ID3_Open {fname {debug 0}} {
  global gID3Data 

  set fd [open $fname]
  fconfigure $fd -translation binary
  set gID3Data($fd,currHandle) 0
  set gID3Data($fd,size) 0
  set gID3Data($fd,padding) 0

  if {[catch {ID3_Read_Header $fd}]} {
    error "valid ID3 header not found in \"$fname\""
  }
  while {$gID3Data($fd,size) < $gID3Data($fd,sizeInHeader)} {
    set frameHeader [read $fd 1]
    if {$frameHeader == [string repeat \x00 1]} {
      set gID3Data($fd,padding) \
          [expr $gID3Data($fd,sizeInHeader) - $gID3Data($fd,size)]
      seek $fd $gID3Data($fd,sizeInHeader)
      break
    } else {
      append frameHeader [read $fd 9]
        
      binary scan $frameHeader A4 id
      binary scan $frameHeader @4I size
      set data [read $fd $size]

      ID3_Add_Frame $fd $id $frameHeader $data

      if {$debug} {
        puts "Read $id frame: $size bytes"
      }
    }
  }
  if {$debug} {
    puts "ID3 Size: $gID3Data($fd,sizeInHeader) \
          (read $gID3Data($fd,size) bytes, $gID3Data($fd,padding) bytes padding)\n"
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
    unset gID3Data($fd,$i,data)
    unset gID3Data($fd,$i,header)
  }
  unset gID3Data($fd,size)
  unset gID3Data($fd,sizeInHeader)
  unset gID3Data($fd,currHandle)
  unset gID3Data($fd,header)
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

proc ID3_Get_Frame_Handle {fd id} {
  global gID3Data
  return $gID3Data($fd,h$id)
}

proc ID3_Get_Frame_ID {fd handle} {
  global gID3Data
  return $gID3Data($fd,$handle,id)
}

proc ID3_Get_Frame_Header {fd handle} {
  global gID3Data
  return $gID3Data($fd,$handle,header)
}

proc ID3_Get_Frame_Data {fd handle} {
  global gID3Data
  return $gID3Data($fd,$handle,data)
}

proc ID3_Get_Frame_Text {fd handle} {
  binary scan [ID3_Get_Frame_Data $fd $handle] A* txt
  return [string range $txt 1 end] ;# skip text encoding byte
}

proc ID3_Get_Header {fd} {
  global gID3Data
  return $gID3Data($fd,header)
}

proc ID3_Dump_Cover {fd} {
  set handle [ID3_Get_Frame_Handle $fd APIC]
  set data [ID3_Get_Frame_Data $fd $handle]

  set idx 1 ;# skip encoding
  set mime [lindex [split [string range $data $idx end] \x00] 0]
  incr idx [expr [string length $mime] + 1] ;# skip null byte
  incr idx ;# skip picture type
  set desc [lindex [split [string range $data  $idx end] \x00] 0]
  incr idx [expr [string length $desc] + 1] ;# skip null byte

  set fname cover.[string range $mime [expr [string first / $mime] + 1] end]
  set out [open $fname w]
  fconfigure $out -translation binary -encoding binary
  puts $out [string range $data $idx end]
  close $out
}

proc Print_Table {title cols colWidths rows} {
  set width -1
  set sep +
  set fmt "|"
  foreach w $colWidths {
    append sep -[string repeat - $w]-+
    incr width [expr $w + 3] ;# margins
    append fmt " %-${w}s |"
  }
  puts +[string repeat - $width]+
  set diff [expr $width - [string length $title]]
  set padLeft [expr $diff / 2]
  set padRight [expr $padLeft + [expr $diff % 2]]
  set title [string repeat " " $padLeft]$title[string repeat " " $padRight]
  puts |$title|
  puts $sep
  puts [eval format \$fmt $cols]
  puts $sep
  foreach r $rows {
    puts [eval format \$fmt $r]
  }
  puts $sep
}

# begin program

if {[catch {Parse_Args} err]} {
  puts stderr $err
  puts stderr [Usage_String]
  exit 1
}

if {[catch {set id3 [ID3_Open [Get_Setting fname] [Get_Setting verbose]]} err]} {
  puts stderr $err
  exit 1
}

set scriptdir [file dirname [info script]]
source [file join $scriptdir frameids.tcl]
source [file join $scriptdir genres.tcl]

for {set i 0} {$i < [ID3_Num_Frames $id3]} {incr i} {
  set fid [ID3_Get_Frame_ID $id3 $i]

  if {[Get_Setting verbose]} {
    set header [ID3_Get_Frame_Header $id3 $i]
    binary scan $header @4I size
    binary scan $header @8S flags
    lappend headertbl [list $fid $size \
      [expr $flags & 0x8000] \
      [expr $flags & 0x4000] \
      [expr $flags & 0x2000] \
      [expr $flags & 0x0080] \
      [expr $flags & 0x0040] \
      [expr $flags & 0x0020]]
  }

  if {[info exists frameids($fid)]} {
    set txt [ID3_Get_Frame_Text $id3 $i]
    if {$fid eq "TCON"} {
      catch {
        set txt $genres([lindex [regexp -inline {\((\d\d)\)} $txt] 1])
      }
    }
    lappend txttbl [list "$fid ($frameids($fid))" $txt]
  } 
}

Print_Table "ID3 Text Information Frames" {Frame Value} {50 40} $txttbl

if {[Get_Setting verbose]} {
  set header [ID3_Get_Header $id3]
  binary scan $header A3 fileident
  binary scan $header @3c major
  binary scan $header @4c rev
  binary scan $header @5c flags
  set size [ID3_Size_To_Int [string range $header end-3 end]]

  puts {}
  Print_Table "ID3 Header Info" \
    {Field Value} \
    {30    8    } \
    [list [list "File identifier"        $fileident] \
          [list "Version"                v${major}.${rev}] \
          [list "Size"                   $size] \
          [list "Unsynchronization"      [expr $flags & 0x80]] \
          [list "Extended header"        [expr $flags & 0x40]] \
          [list "Experimental indicator" [expr $flags & 0x20]]]

  puts {}
  Print_Table "Frame Header Info" \
    {Frame Size a b c i j k} \
    {5     9    1 1 1 1 1 1} \
    $headertbl
  puts \
"
Flags
--------------------------------------------------
a - Tag alter preservation
      0   Frame should be preserved
      1   Frame should be discarded
b - File alter preservation
      0   Frame should be preserved
      1   Frame should be discarded
c - Read only
i - Compression
      0   Frame is not compressed
      1   Frame is compressed using zlib
j - Encryption
      0   Frame is not encrypted
      1   Frame is encrypted
k - Grouping identity
      0   Frame does not contain group information
      1   Frame contains group information
"
}

if {[Get_Setting dump_cover]} {
  ID3_Dump_Cover $id3
}

ID3_Close $id3
