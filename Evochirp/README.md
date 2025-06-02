
# 🐦 EvoChirp: Bird Song Generator



---

## 📚 Overview

**EvoChirp** is a bird song evolution simulator written in **x86-64 Assembly Language**.  
It models how different bird species—Sparrows, Warblers, and Nightingales—evolve their songs through a sequence of operations.

Each species follows unique transformation rules for operations like merging notes, repeating patterns, reducing sequences, and harmonizing. The program processes input commands and outputs the song after each evolutionary generation.

---

## 🛠️ Features

- 🎵 **Species-Specific Transformations**:
  - **Sparrow**:
    - `+`: Merge last two notes (X Y → X-Y)
    - `*`: Repeat last note (X → X X)
    - `-`: Remove first occurrence of the softest note (C < T < D)
    - `H`: Transform C↔T and D→D-T
  - **Warbler**:
    - `+`: Replace last two notes with "T-C"
    - `*`: Duplicate last two notes (X Y → X Y X Y)
    - `-`: Remove the last note
    - `H`: Append a "T" at the end
  - **Nightingale**:
    - `+`: Duplicate last two notes (X Y → X Y X Y)
    - `*`: Repeat the entire sequence
    - `-`: Remove one note if the last two notes are identical
    - `H`: Rearrange last three notes (X Y Z → X-Z Y-X)

- 🧠 **Efficient Memory Management**:
  - Fixed-size buffers for sequences and transformations.
  - No external libraries; uses only Linux syscalls for I/O.

- 💻 **System-Level Programming**:
  - Direct interaction with Linux system calls.
  - Low-level memory operations and buffer handling.

---

## 📂 Project Structure

```
.
├── evochirp.s      # Main assembly source file
├── Report.pdf      # Detailed project report
```

---

## 🚀 Getting Started

### 🔧 Requirements

- Linux environment (x86-64 architecture)
- `gcc` (GNU Compiler Collection)

### 🛠️ Compilation

```bash
gcc -no-pie -o evochirp evochirp.s
```

### ▶️ Running the Program

```bash
./evochirp
```

The program reads from **stdin**. Example:

```bash
echo "Sparrow C T D + * -" | ./evochirp
```

---

## 📝 Example Interaction

**Input:**
```text
Sparrow C T D + * -
```

**Output:**
```text
Sparrow Gen 0: C T-D
Sparrow Gen 1: C T-D T-D
Sparrow Gen 2: T-D T-D
```

---

## 🔤 Supported Operators

| Operator | Description                       |
|---------|------------------------------------|
| `+`     | Merge / Duplicate notes            |
| `*`     | Repeat notes                       |
| `-`     | Reduce / Remove notes              |
| `H`     | Harmonize / Transform sequences    |

---

## 🧩 Implementation Details

- **Memory Buffers**:
  - `read_buffer`: Read user input.
  - `out_buffer`: Build and output generation results.
  - `sequence_buf`: Store the sequence of bird notes (max 128 notes, 64 bytes each).
  - `temp1`, `temp2`: Temporary buffers for note transformations.

- **System Calls**:
  - `sys_read`: Read from standard input.
  - `sys_write`: Write output to standard output.
  - `sys_exit`: Exit the program.

- **Control Flow**:
  - Parse bird species and initialize sequence.
  - Process each token (note or operator) sequentially.
  - Apply species-specific transformations per operation.
  - Output the sequence after every operation (generation).

---

## 🧑‍💻 Author

**Ethem Erinç Cengiz**  
📧 Email: erinccengiz@gmail.com  
🔗 [GitHub Profile](https://github.com/erinc00)

---
