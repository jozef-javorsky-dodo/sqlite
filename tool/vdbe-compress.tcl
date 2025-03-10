#!/usr/bin/tcl
#
# This script makes modifications to the vdbe.c source file which reduce
# the amount of stack space required by the sqlite3VdbeExec() routine.
#
# The modifications performed by this script are optional.  The vdbe.c
# source file will compile correctly with and without the modifications
# performed by this script.  And all routines within vdbe.c will compute
# the same result.  The modifications made by this script merely help
# the C compiler to generate code for sqlite3VdbeExec() that uses less
# stack space.
#
# Script usage:
#
#          mv vdbe.c vdbe.c.template
#          tclsh vdbe-compress.tcl $CFLAGS <vdbe.c.template >vdbe.c
#
# Modifications made:
#
# All modifications are within the sqlite3VdbeExec() function.  The
# modifications seek to reduce the amount of stack space allocated by
# this routine by moving local variable declarations out of individual
# opcode implementations and into a single large union.  The union contains
# a separate structure for each opcode and that structure contains the
# local variables used by that opcode.  In this way, the total amount
# of stack space required by sqlite3VdbeExec() is reduced from the
# sum of all local variables to the maximum of the local variable space
# required for any single opcode.
#
# In order to be recognized by this script, local variables must appear
# on the first line after the open curly-brace that begins a new opcode
# implementation.  Local variables must not have initializers, though they
# may be commented.
#
# The union definition is inserted in place of a special marker comment
# in the preamble to the sqlite3VdbeExec() implementation.
#
#############################################################################
#
set beforeUnion {}   ;# C code before union
set unionDef {}      ;# C code of the union
set afterUnion {}    ;# C code after the union
set sCtr 0           ;# Context counter

# If the SQLITE_SMALL_STACK compile-time option is missing, then
# this transformation becomes a no-op.
#
if {![regexp {SQLITE_SMALL_STACK} $argv]} {
  while {![eof stdin]} {
    puts [gets stdin]
  }
  exit
}

# Read program text up to the spot where the union should be
# inserted.
#
while {![eof stdin]} {
  set line [gets stdin]
  if {[regexp {INSERT STACK UNION HERE} $line]} break
  append beforeUnion $line\n
}

# Process the remaining text.  Build up the union definition as we go.
#
set vlist {}
set seenDecl 0
set namechars {abcefghjklmnopqrstuvwxyz}
set nnc [string length $namechars]
while {![eof stdin]} {
  set line [gets stdin]
  if {[regexp "^case (OP_\\w+): \\x7B" $line all operator]} {
    append afterUnion $line\n
    set vlist {}
    while {![eof stdin]} {
      set line [gets stdin]
      if {[regexp {^ +(const )?\w+ \**(\w+)(\[.*\])?;} $line \
           all constKeyword vname notused1]} {
        if {!$seenDecl} {
          set sname {}
          append sname [string index $namechars [expr {$sCtr/$nnc}]]
          append sname [string index $namechars [expr {$sCtr%$nnc}]]
          incr sCtr
          append unionDef "    struct ${operator}_stack_vars \173\n"
          append afterUnion \
             "#if 0  /* local variables moved into u.$sname */\n"
          set seenDecl 1
        }
        append unionDef "    $line\n"
        append afterUnion $line\n
        lappend vlist $vname
      } elseif {[regexp {^#(if|endif)} $line] && [llength $vlist]>0} {
        append unionDef "$line\n"
        append afterUnion $line\n
      } else {
        break
      }
    }
    if {$seenDecl} {
      append unionDef   "    \175 $sname;\n"
      append afterUnion "#endif /* local variables moved into u.$sname */\n"
    }
    set seenDecl 0
  }
  if {[regexp "^\175" $line]} {
    append afterUnion $line\n
    set vlist {}
  } elseif {[llength $vlist]>0} {
    append line " "
    foreach v $vlist {
      regsub -all "(\[^a-zA-Z0-9>.\])${v}(\\W)" $line "\\1u.$sname.$v\\2" line
      regsub -all "(\[^a-zA-Z0-9>.\])${v}(\\W)" $line "\\1u.$sname.$v\\2" line

      # The expressions above fail to catch instance of variable "abc" in
      # expressions like (32>abc). The following expression makes those
      # substitutions.
      regsub -all "(\[^-\])>${v}(\\W)" $line "\\1>u.$sname.$v\\2" line
    }
    append afterUnion [string trimright $line]\n
  } elseif {$line=="" && [eof stdin]} {
    # no-op
  } else {
    append afterUnion $line\n
  }
}

# Output the resulting text.
#
puts -nonewline $beforeUnion
puts "  /********************************************************************"
puts "  ** Automatically generated code"
puts "  **"
puts "  ** The following union is automatically generated by the"
puts "  ** vdbe-compress.tcl script.  The purpose of this union is to"
puts "  ** reduce the amount of stack space required by this function."
puts "  ** See comments in the vdbe-compress.tcl script for details."
puts "  */"
puts "  union vdbeExecUnion \173"
puts -nonewline $unionDef
puts "  \175 u;"
puts "  /* End automatically generated code"
puts "  ********************************************************************/"
puts -nonewline $afterUnion
