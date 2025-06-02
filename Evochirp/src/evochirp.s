.section .bss
.align 8
# Buffers for input/output and song storage
read_buffer:    .space 512       # Input buffer for reading from stdin
out_buffer:     .space 10240     # Output buffer for formatted results
sequence_buf:   .space 8192      # Stores the sequence of bird notes (64 bytes per note)
temp1:          .space 64        # Temporary buffer for string operations
temp2:          .space 64        # Secondary temporary buffer
note_count:     .quad 0          # Current number of notes in sequence
generation:     .quad 0          # Current generation counter
species_id:     .quad 0          # 0=Sparrow, 1=Warbler, 2=Nightingale

.section .text
.global _start
_start:
    # Read initial input from stdin
    mov     $0, %rax
    mov     $0, %rdi
    lea     read_buffer(%rip), %rsi
    mov     $512, %rdx
    syscall
    cmp     $0, %rax
    jle     exit

# Find newline in input and null-terminate the first line
find_nl:
    mov     %rax, %rcx
    lea     read_buffer(%rip), %rdi
find_nl_loop:
    cmp     $0, %rcx
    je      no_newline
    movb    (%rdi), %al
    cmpb    $'\n', %al
    je      found_nl
    inc     %rdi
    dec     %rcx
    jmp     find_nl_loop
found_nl:
    movb    $0, (%rdi)
no_newline:

    # Parse bird species from input (first token before space)
    lea     read_buffer(%rip), %rdi
parse_species:
    movb    (%rdi), %al
    cmpb    $0, %al
    je      no_species
    cmpb    $' ', %al
    je      species_done
    inc     %rdi
    jmp     parse_species
no_species:
    jmp exit
species_done:
    movb    $0, (%rdi)

    # Set species_id based on first character of species name
    lea     read_buffer(%rip), %rsi
    movb    (%rsi), %al
    cmpb    $'S', %al
    je      set_sparrow
    cmpb    $'W', %al
    je      set_warbler
    cmpb    $'N', %al
    je      set_nightingale
    movl    $0, species_id(%rip)
    jmp     species_set
set_sparrow:
    movl    $0, species_id(%rip)
    jmp     species_set
set_warbler:
    movl    $1, species_id(%rip)
    jmp     species_set
set_nightingale:
    movl    $2, species_id(%rip)
species_set:
    inc     %rdi

# Initialize song state
    movq    $0, note_count(%rip)
    movq    $0, generation(%rip)

# Main token processing loop
token_loop:
skip_spaces:
    movb    (%rdi), %al
    cmpb    $0, %al
    je      done_parsing
    cmpb    $' ', %al
    jne     token_start
    inc     %rdi
    jmp     skip_spaces

# Process next token (note or operator)
token_start:
    movb    (%rdi), %al
    cmpb    $0, %al         #check end of input
    je      done_parsing
    cmpb    $'+', %al       #check merge opeartor
    je      op_plus         #jump to op_plus part
    cmpb    $'*', %al       #check repeat operator
    je      op_star         #jump to op_star part  
    cmpb    $'-', %al       #check reduce oparetor
    je      op_reduce       #jump to op_reduce part
    cmpb    $'H', %al       #check harmonize operator
    je      op_harmonize    #jump to op_harmonize part

# Add note to sequence
add_note:
    movq    note_count(%rip), %rbx
    movq    %rbx, %rcx
    shl     $6, %rcx
    lea     sequence_buf(%rip), %rsi
    add     %rcx, %rsi          #Compute destination address
    movb    %al, (%rsi)         #Store note byte         
    movb    $0, 1(%rsi)                  
    incq    note_count(%rip)    #note_count++
    inc     %rdi                #Advance past note  
    jmp     token_loop

# -------------------------------
# Operator handlers (species-specific)
# -------------------------------

# '+' Operator: Merge notes behavior
op_plus:
    inc     %rdi
    push    %rdi
    movl    species_id(%rip), %ebx
    # Branch to species-specific merge implementations
    cmpl    $0, %ebx
    je      plus_sparrow    # Sparrow: merge last two notes (X Y -> X-Y)
    cmpl    $1, %ebx
    je      plus_warbler    # Warbler: merge last two into "T-C"
    cmpl    $2, %ebx
    je      plus_nightingale # Nightingale: duplicate last two notes (X Y -> X Y X Y)
    jmp     output_generation

# Sparrow '+' implementation
plus_sparrow:
    movq    note_count(%rip), %rcx
    cmpq    $2, %rcx
    jl      output_generation   # Need at least 2 notes to merge

    # Check if last note is already merged (contains '-')
    movq    %rcx, %rax
    subq    $1, %rax
    movq    %rax, %r9
    shl     $6, %r9
    lea     sequence_buf(%rip), %r10
    add     %r9, %r10
scan_j:
    movb    (%r10), %al
    cmpb    $0, %al                  # Check for null terminator
    je      scan_i                   #if end-of-string, OK to scan previous
    cmpb    $'-', %al                #Detect merge marker
    je      output_generation        # skip if this slot is already merged
    inc     %r10
    jmp     scan_j

# Check if second-last note is merged
scan_i:
    movq    %rcx, %rax
    subq    $2, %rax
    movq    %rax, %r9
    shl     $6, %r9
    lea     sequence_buf(%rip), %r10
    add     %r9, %r10
scan_i_dash:
    movb    (%r10), %al
    cmpb    $0, %al                 #Check for null terminator
    je      do_merge_sparrow        # Validation passed - perform merge 
    cmpb    $'-', %al
    je      output_generation       #Abort: note already contains hyphen
    inc     %r10
    jmp     scan_i_dash             # Continue scanning

# Perform the merge of last two notes
do_merge_sparrow:
    # Get pointers to last two notes
    movq    %rcx, %rbx
    subq    $2, %rbx                        # i = note_count - 2
    movq    %rcx, %rax
    subq    $1, %rax                        # j = note_count - 1
    movq    %rbx, %r8
    shl     $6, %r8
    lea     sequence_buf(%rip), %r9
    add     %r8, %r9
    movq    %rax, %r10
    shl     $6, %r10
    lea     sequence_buf(%rip), %rsi
    add     %r10, %rsi

    # Build merged note in temp1 (X-Y format)
    lea     temp1(%rip), %rdi
copy_X:
    movb    (%r9), %al
    cmpb    $0, %al
    je      X_copied
    movb    %al, (%rdi)
    inc     %r9
    inc     %rdi
    jmp     copy_X
X_copied:
    movb    $'-', (%rdi)                   # insert dash between notes
    inc     %rdi
copy_Y:
    movb    (%rsi), %al                    # load next char from Y
    cmpb    $0, %al
    je      Y_copied
    movb    %al, (%rdi)                     # store into temp1
    inc     %rsi
    inc     %rdi
    jmp     copy_Y
Y_copied:
    movb    $0, (%rdi)                     # terminate merged string

    # Update sequence: remove last two, add merged note
    movq    note_count(%rip), %rax
    subq    $1, %rax
    movq    %rax, note_count(%rip)
    subq    $1, %rax
    movq    %rax, note_count(%rip)
    
    # Compute target slot for merged note (reuse index i)
    movq    %rax, %rbx                     # index for new merged note
    shl     $6, %rbx
    lea     sequence_buf(%rip), %r9
    add     %rbx, %r9                      # target slot for merged note (reuse index i)
    lea     temp1(%rip), %rdi
copy_merged:
    movb    (%rdi), %al
    movb    %al, (%r9)
    inc     %rdi
    inc     %r9
    cmpb    $0, %al
    jne     copy_merged
    incq    note_count(%rip)
    jmp     output_generation

# Warbler '+' implementation (merge to "T-C")
plus_warbler:
    movq    note_count(%rip), %rcx
    cmpq    $2, %rcx
    jl      output_generation             # if fewer than 2 notes available, skip merge

    # Check if last note is merged
    movq    %rcx, %rax
    subq    $1, %rax
    movq    %rax, %r9
    shl     $6, %r9
    lea     sequence_buf(%rip), %r10
    add     %r9, %r10
scan_j_w:
    movb    (%r10), %al
    cmpb    $0, %al
    je      scan_i_w                  # end of string, no '-' found
    cmpb    $'-', %al
    je      output_generation         # if merged note, do not apply
    inc     %r10
    jmp     scan_j_w                  # keep scanning bytes 

# Check if second-last note is merged
scan_i_w:
    movq    %rcx, %rax
    subq    $2, %rax
    movq    %rax, %r9
    shl     $6, %r9
    lea     sequence_buf(%rip), %r10
    add     %r9, %r10
scan_i2_w:
    movb    (%r10), %al
    cmpb    $0, %al
    je      do_merge_warbler          # end of note i, safe to merge
    cmpb    $'-', %al
    je      output_generation         # if note i is merged, skip  
    inc     %r10
    jmp     scan_i2_w

# Perform Warbler merge (replace last two with "T-C")
do_merge_warbler:
    # Remove the last two notes by decrementing count twice
    movq    %rcx, %rax
    subq    $1, %rax
    movq    %rax, note_count(%rip)
    subq    $1, %rax
    movq    %rax, note_count(%rip)

    # Place melodic call "T-C" as new note
    movq    %rax, %rbx                    # index for new note (old count-2)
    shl     $6, %rbx
    lea     sequence_buf(%rip), %r14
    add     %rbx, %r14                    # R14 -> start of new slot
    movb    $'T', (%r14)
    movb    $'-', 1(%r14)
    movb    $'C', 2(%r14)
    movb    $0, 3(%r14)                   # null-terminate string

    # Increment count to account for the new note
    movq    note_count(%rip), %rax
    incq    %rax
    movq    %rax, note_count(%rip)
    jmp     output_generation             # finish and print generation 

# Nightingale '+' implementation (duplicate last two notes)
plus_nightingale:
    movq    note_count(%rip), %rcx
    cmpq    $2, %rcx
    jl      output_generation               # if less than 2 notes, do nothing

    # Check if last note is merged
    movq    %rcx, %rax
    subq    $1, %rax
    movq    %rax, %r9
    shl     $6, %r9
    lea     sequence_buf(%rip), %r10
    add     %r9, %r10
scan_j_n:
    movb    (%r10), %al
    cmpb    $0, %al
    je      scan_i_n            # end of string, no dash
    cmpb    $'-', %al
    je      output_generation   # merged note, skip
    inc     %r10
    jmp     scan_j_n

# Check if second-last note is merged
scan_i_n:
    movq    %rcx, %rax
    subq    $2, %rax
    movq    %rax, %r9
    shl     $6, %r9
    lea     sequence_buf(%rip), %r10
    add     %r9, %r10
scan_i2_n:
    movb    (%r10), %al
    cmpb    $0, %al
    je      do_merge_nightingale        # end of string, no dash
    cmpb    $'-', %al
    je      output_generation           # merged note, skip
    inc     %r10
    jmp     scan_i2_n

# Perform Nightingale duplicate operation
do_merge_nightingale:
    # Get pointers to last two notes
    movq    %rcx, %rbx          # RBX = count
    subq    $2, %rbx            # RBX = i index
    movq    %rcx, %rax          # RAX = count
    subq    $1, %rax            # RAX = j index
    movq    %rbx, %r8
    shl     $6, %r8
    lea     sequence_buf(%rip), %r9
    add     %r8, %r9            # R9 -> source note i
    movq    %rax, %r10
    shl     $6, %r10
    lea     sequence_buf(%rip), %r11
    add     %r10, %r11          # R11 -> source note j

    # Append copies of these two notes
    movq    note_count(%rip), %rsi
    shl     $6, %rsi
    lea     sequence_buf(%rip), %rbp
    add     %rsi, %rbp          # RBP -> target for copy of note i
    movq    %r9, %r8            # R8 -> ptr to source note i
copy_i_night_plus:
    movb    (%r8), %al
    movb    %al, (%rbp)
    inc     %r8
    inc     %rbp
    cmpb    $0, %al
    jne     copy_i_night_plus

    # Append note j
    movq    note_count(%rip), %rax
    addq    $1, %rax            # target index = old count + 1
    movq    %rax, %rsi
    shl     $6, %rsi
    lea     sequence_buf(%rip), %rbp
    add     %rsi, %rbp          # RBP -> target for copy of note j
    movq    %r11, %r8           # R8 -> ptr to source note j
copy_j_night_plus:
    movb    (%r8), %al
    movb    %al, (%rbp)
    inc     %r8
    inc     %rbp
    cmpb    $0, %al
    jne     copy_j_night_plus

    # Update note_count to include the two new notes
    movq    note_count(%rip), %rax
    addq    $2, %rax
    movq    %rax, note_count(%rip)
    jmp     output_generation  # print generation and continue

# '*' Operator: Repeat notes behavior
op_star:
    inc     %rdi              # skip '*'
    push    %rdi
    movl    species_id(%rip), %ebx
    # Branch to species-specific repeat implementations
    cmpl    $0, %ebx
    je      star_sparrow      # Sparrow: repeat last note (X -> X X)
    cmpl    $1, %ebx
    je      star_warbler      # Warbler: echo last two notes (X Y -> X Y X Y)
    cmpl    $2, %ebx
    je      star_nightingale  # Nightingale: repeat entire sequence (S -> S S)
    jmp     output_generation # no valid species → print unchanged

# Sparrow '*' implementation
star_sparrow:
    movq    note_count(%rip), %rcx      # RCX = current note count
    cmpq    $1, %rcx
    jl      output_generation           # nothing to do if <1 note

    # Copy last note to next slot
    movq    %rcx, %rax
    subq    $1, %rax                    # RAX = last-note index
    movq    %rax, %r8
    shl     $6, %r8                     # scale by 64 bytes per entry
    lea     sequence_buf(%rip), %r9
    add     %r8, %r9                    # R9 → source note string

    # Compute destination pointer: address of new slot (index = note_count)
    movq    %rcx, %rbx                  # RBX = original note_count
    shl     $6, %rbx                    # scale by 64
    lea     sequence_buf(%rip), %r11
    add     %rbx, %r11                  # R11 → target slot

copy_note_sparrow:
    movb    (%r9), %al
    movb    %al, (%r11)
    inc     %r9                         
    inc     %r11                        
    cmpb    $0, %al
    jne     copy_note_sparrow           # repeat until null terminator
    incq    note_count(%rip)            
    jmp     output_generation           # format & print updated song

# Warbler '*' implementation
star_warbler:
    movq    note_count(%rip), %rcx
    cmpq    $2, %rcx
    jl      output_generation               # need at least two notes, otherwise no change
    # Get pointers to last two notes
    movq    %rcx, %rbx
    subq    $2, %rbx
    movq    %rcx, %rax
    subq    $1, %rax
    movq    %rbx, %r8
    shl     $6, %r8
    lea     sequence_buf(%rip), %r9
    add     %r8, %r9
    movq    %rax, %r10
    shl     $6, %r10
    lea     sequence_buf(%rip), %r11
    add     %r10, %r11

    # Append copies of these two notes
    movq    note_count(%rip), %rsi
    shl     $6, %rsi
    lea     sequence_buf(%rip), %rbp
    add     %rsi, %rbp
    movq    %r9, %r8
copy_i_warbler:
    movb    (%r8), %al
    movb    %al, (%rbp)
    inc     %r8
    inc     %rbp
    cmpb    $0, %al
    jne     copy_i_warbler              # repeat until null terminator

    # Compute destination for second appended copy
    movq    note_count(%rip), %rax
    addq    $1, %rax
    movq    %rax, %rsi
    shl     $6, %rsi
    lea     sequence_buf(%rip), %rbp
    add     %rsi, %rbp
    movq    %r11, %r8
copy_j_warbler:
    movb    (%r8), %al
    movb    %al, (%rbp)
    inc     %r8
    inc     %rbp
    cmpb    $0, %al
    jne     copy_j_warbler              # repeat until null terminator
    movq    note_count(%rip), %rax
    addq    $2, %rax
    movq    %rax, note_count(%rip)
    jmp     output_generation           # build and print updated generation

# Nightingale '*' implementation
star_nightingale:
    movq    note_count(%rip), %rcx

    # If fewer than 2 notes, do nothing
    cmpq    $1, %rcx
    jl      output_generation
    # Duplicate entire sequence
    movq    %rcx, %rbx
    xor     %r8, %r8
repeat_loop_night:
    # If we've copied all original notes, exit loop
    cmpq    %rbx, %r8
    jge     repeat_done_night

    # Get pointer to note i in original sequence
    movq    %r8, %r10
    shl     $6, %r10
    lea     sequence_buf(%rip), %r11
    add     %r10, %r11

    # Get pointer to new note position
    movq    note_count(%rip), %rsi
    addq    %r8, %rsi
    shl     $6, %rsi
    lea     sequence_buf(%rip), %rbp
    add     %rsi, %rbp
copy_note_night:
    movb    (%r11), %al
    movb    %al, (%rbp)
    inc     %r11
    inc     %rbp
    cmpb    $0, %al             # Check for end-of-string (null terminator)
    jne     copy_note_night     # Continue copying bytes if not at end
    inc     %r8
    jmp     repeat_loop_night   # Repeat for next original note
repeat_done_night:
    # After copying, increment note_count by original sequence length
    movq    note_count(%rip), %rax
    addq    %rbx, %rax
    movq    %rax, note_count(%rip)
    jmp     output_generation   # Build and print the updated generation line

# '-' Operator: Reduce notes behavior
op_reduce:
    inc     %rdi                      # skip past '-' token
    push    %rdi                      # save parser position for output
    movl    species_id(%rip), %ebx
    # Branch to species-specific reduce implementations
    cmpl    $0, %ebx
    je      reduce_sparrow    # Sparrow: remove first softest note
    cmpl    $1, %ebx
    je      reduce_warbler    # Warbler: remove last note
    cmpl    $2, %ebx
    je      reduce_nightingale # Nightingale: remove one if last two identical
    jmp     output_generation

# Sparrow '-' implementation
reduce_sparrow:
    movq    note_count(%rip), %rcx
    cmpq    $1, %rcx
    jl      output_generation       # nothing to remove if fewer than 2 notes

    # Find softest note (C < T < D) and remove first occurrence
    xor     %r8, %r8
    movb    $0, %bl

# Search for 'C' (softest)
find_chirp:
    cmpq    %rcx, %r8
    jge     check_trill             # if reached end, move on to T
    movq    %r8, %r9
    shl     $6, %r9
    lea     sequence_buf(%rip), %r10
    add     %r9, %r10

    # skip merged notes
    movb    1(%r10), %al
    cmpb    $'-', %al
    je      next_note_C

    movq    %r8, %r10
    shl     $6, %r10
    lea     sequence_buf(%rip), %r11
    add     %r10, %r11
    movb    $0, %bl
scan_for_C:
    movb    (%r11), %al
    cmpb    $0, %al
    je      next_note_C         # end of string: no C here
    cmpb    $'C', %al
    je      found_C
    inc     %r11
    jmp     scan_for_C
next_note_C:
    inc     %r8
    jmp     find_chirp
found_C:
    jmp     remove_note         # jump to common removal

# If no 'C', search for 'T'
check_trill:    
    xor     %r8, %r8            # reset index for T search
find_trill:
    cmpq    %rcx, %r8
    jge     check_deep          # if end reached, try D
    movb    1(%r11), %al
    cmpb    $'-', %al
    je      next_note_T
    movq    %r8, %r10
    shl     $6, %r10
    lea     sequence_buf(%rip), %r11
    add     %r10, %r11
    movb    $0, %bl
scan_for_T:
    movb    (%r11), %al
    cmpb    $0, %al
    je      next_note_T
    cmpb    $'T', %al
    je      found_T
    inc     %r11
    jmp     scan_for_T
next_note_T:
    inc     %r8
    jmp     find_trill
    found_T:
    jmp     remove_note

# If no 'T', search for 'D'
check_deep:
    xor     %r8, %r8
find_deep:
    cmpq    %rcx, %r8
    jge     output_generation           # no notes left to remove
    movq    %r8, %r10
    shl     $6, %r10
    lea     sequence_buf(%rip), %r11
    add     %r10, %r11
    movb    1(%r11), %al
    cmpb    $'-', %al
    je      next_note_D
scan_for_D:
    movb    (%r11), %al
    cmpb    $0, %al
    je      next_note_D
    cmpb    $'D', %al
    je      found_D
    inc     %r11
    jmp     scan_for_D
    next_note_D:
    inc     %r8
    jmp     find_deep
    found_D:
    jmp     remove_note

# Common note removal logic
remove_note:
    movq    note_count(%rip), %rax
    cmpq    %r8, %rax
    jle     output_generation
    movq    note_count(%rip), %rbx
    subq    $1, %rbx
    cmpq    %rbx, %r8
    je      pop_last

# Shift notes left to overwrite removed note
shift_loop:
    cmpq    %rbx, %r8
    jge     shift_done
    movq    %r8, %r11
    addq    $1, %r11
    movq    %r11, %r12
    shl     $6, %r12
    lea     sequence_buf(%rip), %r13
    add     %r12, %r13
    movq    %r8, %r14
    shl     $6, %r14
    lea     sequence_buf(%rip), %r15
    add     %r14, %r15
copy_shift:
    movb    (%r13), %al
    movb    %al, (%r15)
    inc     %r13
    inc     %r15
    cmpb    $0, %al
    jne     copy_shift
    inc     %r8
    jmp     shift_loop
shift_done:
pop_last:
    movq    note_count(%rip), %rax
    subq    $1, %rax
    movq    %rax, note_count(%rip)
    jmp     output_generation

# Warbler '-' implementation
reduce_warbler:
    movq    note_count(%rip), %rcx
    cmpq    $1, %rcx
    jl      output_generation       # nothing to do if no notes
    # Check if last note is merged
    movq    %rcx, %rax
    subq    $1, %rax
    movq    %rax, %r9
    shl     $6, %r9
    lea     sequence_buf(%rip), %r10
    add     %r9, %r10
scan_last_w:
    movb    (%r10), %al
    cmpb    $0, %al
    je      do_reduce_w
    cmpb    $'-', %al
    je      output_generation       # merged note: skip
    inc     %r10
    jmp     scan_last_w
do_reduce_w:
    decq    note_count(%rip)        # drop the last note
    jmp     output_generation

# Nightingale '-' implementation
reduce_nightingale:
    movq    note_count(%rip), %rcx
    cmpq    $2, %rcx                # need at least two notes
    jl      output_generation   
    # Check if last two notes are identical (and not merged)
    movq    %rcx, %rax
    subq    $2, %rax
    movq    %rax, %rbx
    movq    %rcx, %rdx
    subq    $1, %rdx
    movq    %rdx, %r8
    movq    %rbx, %r9
    shl     $6, %r9
    lea     sequence_buf(%rip), %r10
    add     %r9, %r10
    movq    %r8, %r11
    shl     $6, %r11
    lea     sequence_buf(%rip), %r12
    add     %r11, %r12

    # Check for dashes (merged notes)
    movq    %r10, %r13
    xor     %bl, %bl
check_dash_i:
    movb    (%r13), %al
    cmpb    $0, %al
    je      no_dash_i
    cmpb    $'-', %al
    je      no_reduce
    inc     %r13
    jmp     check_dash_i
    no_dash_i:
    movq    %r12, %r13
    check_dash_j:
    movb    (%r13), %al
    cmpb    $0, %al
    je      dash_check_done
    cmpb    $'-', %al
    je      no_reduce
    inc     %r13
    jmp     check_dash_j
dash_check_done:

    # Compare last two notes
    movq    %r10, %r13
    movq    %r12, %r14
compare_notes:
    movb    (%r13), %al
    movb    (%r14), %bl
    cmpb    %al, %bl
    jne     no_reduce
    cmpb    $0, %al
    je      notes_equal
    inc     %r13
    inc     %r14
    jmp     compare_notes
notes_equal:
    movq    note_count(%rip), %rax
    subq    $1, %rax
    movq    %rax, note_count(%rip)
no_reduce:
    jmp     output_generation

# 'H' Operator: Harmonize notes behavior
op_harmonize:
    inc     %rdi
    push    %rdi
    movl    species_id(%rip), %ebx
    # Branch to species-specific harmonize implementations
    cmpl    $0, %ebx
    je      harm_sparrow     # Sparrow: transform notes (C<->T, D->D-T)
    cmpl    $1, %ebx
    je      harm_warbler     # Warbler: append 'T'
    cmpl    $2, %ebx
    je      harm_nightingale # Nightingale: rearrange last three notes
    jmp     output_generation

# Sparrow 'H' implementation
harm_sparrow:
    movq    note_count(%rip), %rcx
    cmpq    $1, %rcx
    jl      output_generation       # nothing to do if <1 note
    xor     %r8, %r8
# Transform each note globally
transform_loop:
    cmpq    %rcx, %r8
    jge     transform_done
    movq    %r8, %r9
    shl     $6, %r9
    lea     sequence_buf(%rip), %r10
    add     %r9, %r10

    # Skip if this is a merged note
    movb    1(%r10), %al
    cmpb    $'-', %al
    je      skip_harm_note

    # Prepare to build transformed note in temp1
    lea     temp1(%rip), %r11
    movq    %r10, %r12
transform_note:
    movb    (%r12), %al
    cmpb    $0, %al
    je      note_transformed
    # Apply transformations
    cmpb    $'C', %al
    je      out_T
    cmpb    $'T', %al
    je      out_C
    cmpb    $'D', %al
    je      out_DT
    movb    %al, (%r11)
    inc     %r11
    inc     %r12
    jmp     transform_note
out_T:
    movb    $'T', (%r11)
    inc     %r11
    inc     %r12
    jmp     transform_note
out_C:
    movb    $'C', (%r11)
    inc     %r11
    inc     %r12
    jmp     transform_note
out_DT:
    movb    $'D', (%r11)
    movb    $'-', 1(%r11)
    movb    $'T', 2(%r11)
    add     $3, %r11
    inc     %r12
    jmp     transform_note
note_transformed:
    movb    $0, (%r11)
    # Copy transformed note back
    lea     temp1(%rip), %r11
copy_back:
    movb    (%r11), %al
    movb    %al, (%r10)
    inc     %r11
    inc     %r10
    cmpb    $0, %al
    jne     copy_back
skip_harm_note:
    inc     %r8
    jmp     transform_loop
transform_done:
    jmp     output_generation

# Warbler 'H' implementation
harm_warbler:
    movq    note_count(%rip), %rcx

    # if fewer than 1 note, nothing to do
    cmpq    $1, %rcx
    jl      output_generation

    # Check if last note is merged
    movq    %rcx, %rax
    subq    $1, %rax
    shl     $6, %rax
    lea     sequence_buf(%rip), %r9
    add     %rax, %r9
    movb    1(%r9), %al
    cmpb    $'-', %al
    je      output_generation           # if merged form, skip append

    # Append 'T' to sequence
    movq    %rcx, %rbx
    shl     $6, %rbx
    lea     sequence_buf(%rip), %r9
    add     %rbx, %r9
    movb    $'T', (%r9)
    movb    $0, 1(%r9)
    incq    note_count(%rip)
    jmp     output_generation

# Nightingale 'H' implementation
harm_nightingale:
    movq    note_count(%rip), %rcx

    # need at least 3 notes to harmonize
    cmpq    $3, %rcx
    jl      output_generation

    # Check if any of last three notes are merged
    movq    %rcx, %rax
    subq    $3, %rax
    call    .check_dash_skip        # skip if merged
    movq    %rcx, %rax
    subq    $2, %rax
    call    .check_dash_skip
    movq    %rcx, %rax
    subq    $1, %rax
    call    .check_dash_skip

    # Get pointers to last three notes
    movq    %rcx, %rax
    subq    $3, %rax
    movq    %rax, %rbx
    movq    %rcx, %r8
    subq    $2, %r8
    movq    %rcx, %r9
    subq    $1, %r9
    movq    %rbx, %r10
    shl     $6, %r10
    lea     sequence_buf(%rip), %r11
    add     %r10, %r11
    movq    %r8, %r12
    shl     $6, %r12
    lea     sequence_buf(%rip), %r13
    add     %r12, %r13
    movq    %r9, %r14
    shl     $6, %r14
    lea     sequence_buf(%rip), %r15
    add     %r14, %r15

    # Build new notes: X-Z and Y-X
    lea     temp1(%rip), %rdi
    movq    %r11, %rsi
copy_X_H:
    movb    (%rsi), %al
    cmpb    $0, %al
    je      X_copied_H
    movb    %al, (%rdi)
    inc     %rsi
    inc     %rdi
    jmp     copy_X_H
X_copied_H:
    movb    $'-', (%rdi)            # insert '-'
    inc     %rdi
    movq    %r15, %rsi
copy_Z_H:
    movb    (%rsi), %al
    cmpb    $0, %al
    je      end_new1
    movb    %al, (%rdi)
    inc     %rsi
    inc     %rdi
    jmp     copy_Z_H
end_new1:
    movb    $0, (%rdi)          
    lea     temp2(%rip), %rdi               
    movq    %r13, %rsi
copy_Y_H:
    movb    (%rsi), %al
    cmpb    $0, %al
    je      Y_copied_H
    movb    %al, (%rdi)
    inc     %rsi
    inc     %rdi
    jmp     copy_Y_H
Y_copied_H:
    movb    $'-', (%rdi)
    inc     %rdi
    movq    %r11, %rsi
copy_X2_H:
    movb    (%rsi), %al
    cmpb    $0, %al
    je      end_new2
    movb    %al, (%rdi)
    inc     %rsi
    inc     %rdi
    jmp     copy_X2_H
end_new2:
    movb    $0, (%rdi)

# Update sequence: remove last three, add new two
    movq    note_count(%rip), %rax
    subq    $3, %rax
    movq    %rax, note_count(%rip)

    # append new note1
    movq    %rax, %rbx
    shl     $6, %rbx
    lea     sequence_buf(%rip), %r9
    add     %rbx, %r9
    lea     temp1(%rip), %rdi
copy_new1:
    movb    (%rdi), %al
    movb    %al, (%r9)
    inc     %rdi
    inc     %r9
    cmpb    $0, %al
    jne     copy_new1
    movq    note_count(%rip), %rax
    incq    %rax
    movq    %rax, note_count(%rip)
    
    # append new note2
    movq    note_count(%rip), %rbx
    shl     $6, %rbx
    lea     sequence_buf(%rip), %r9
    add     %rbx, %r9
    lea     temp2(%rip), %rdi
copy_new2:
    movb    (%rdi), %al
    movb    %al, (%r9)
    inc     %rdi
    inc     %r9
    cmpb    $0, %al
    jne     copy_new2
    movq    note_count(%rip), %rax
    incq    %rax
    movq    %rax, note_count(%rip)
    jmp     output_generation

# Helper function to check for merged notes
.check_dash_skip:
    pushq   %rcx
    pushq   %rdi
    # ptr = sequence_buf + rax*64
    movq    %rax, %rdi
    shl     $6, %rdi
    lea     sequence_buf(%rip), %rsi
    add     %rdi, %rsi                  
    movb    1(%rsi), %dl                
    cmpb    $'-', %dl
    popq    %rdi
    popq    %rcx
    je      output_generation
    ret
# Output generation: format and print the current song after an operator
output_generation:
    pop     %r15                         
    lea     read_buffer(%rip), %rsi     
    lea     out_buffer(%rip), %r9       
    # Copy "<Species> " to output
copy_species_name:
    movb    (%rsi), %al
    cmpb    $0, %al
    je      species_copied
    movb    %al, (%r9)
    inc     %rsi
    inc     %r9
    jmp     copy_species_name
species_copied:
    movb    $' ', (%r9)
    inc     %r9
    # Append "Gen " and generation number
    movb    $'G', (%r9)
    movb    $'e', 1(%r9)
    movb    $'n', 2(%r9)
    movb    $' ', 3(%r9)
    add     $4, %r9
    movq    generation(%rip), %rax
    cmpq    $0, %rax
    je      gen_zero
    lea     temp1(%rip), %rsi           
    xor     %rcx, %rcx
conv_loop:
    xor     %rdx, %rdx
    movq    $10, %rbx
    div     %rbx                         
    add     $'0', %dl
    movb    %dl, (%rsi)                 
    inc     %rsi
    inc     %rcx
    cmpq    $0, %rax
    jne     conv_loop
    dec     %rsi
rev_digits:
    movb    (%rsi), %al
    movb    %al, (%r9)
    inc     %r9
    dec     %rsi
    dec     %rcx
    cmpq    $0, %rcx
    jne     rev_digits
    jmp     gen_done
gen_zero:
    movb    $'0', (%r9)
    inc     %r9
gen_done:
    movb    $':', (%r9)
    movb    $' ', 1(%r9)
    add     $2, %r9
    movq    note_count(%rip), %rbx
    xor     %r8, %r8                   
write_note_loop:
    cmpq    %rbx, %r8
    jge     notes_done
    movq    %r8, %r10
    shl     $6, %r10
    lea     sequence_buf(%rip), %r11
    add     %r10, %r11                  
write_note:
    movb    (%r11), %al
    cmpb    $0, %al
    je      note_done
    movb    %al, (%r9)
    inc     %r11
    inc     %r9
    jmp     write_note
note_done:
    movq    note_count(%rip), %r12
    subq    $1, %r12
    cmpq    %r12, %r8
    je      no_space                   
    movb    $' ', (%r9)
    inc     %r9
no_space:
    inc     %r8
    jmp     write_note_loop
notes_done:
    movb    $'\n', (%r9)               
    inc     %r9
    # Write the output line to stdout (syscall write)
    lea     out_buffer(%rip), %rsi
    sub     %rsi, %r9                  
    mov     %r9, %rdx
    mov     $1, %rax
    mov     $1, %rdi
    lea     out_buffer(%rip), %rsi
    syscall
    # Increment generation counter and loop for next token/operator
    movq    generation(%rip), %rax
    incq    %rax
    movq    %rax, generation(%rip)
    mov     %r15, %rdi                 
    jmp     token_loop

done_parsing:
    # Exit program (syscall exit)
exit:
    mov     $60, %rax
    xor     %rdi, %rdi
    syscall
