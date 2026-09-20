NOTE: Obsolete as of 2026/9/20

## Technical Specification: 512 kbps TDM over Differential Manchester Carrier System## 1. System Overview
This specification defines a synchronous, 8-bit Time-Division Multiplexed (TDM) carrier frame designed for implementation in discrete Transistor-Transistor Logic (TTL). The system multiplexes 6 independent 64 kbps CVSD voice channels (or general data channels), an alternating framing clock, and a sub-commutated signaling channel into a single high-speed digital stream.
------------------------------
## 2. Electrical & Modulation Parameters

* Bit Rate (Line Speed): 512 kbps
* Master Clock Frequency: 512 kHz
* Line Encoding: Differential Manchester
* Modulation Rate: 1.024 MBaud (1024 kMaud)
* Maximum Fundamental Frequency: 512 kHz
* Logic Level Compatibility: Standard 5V TTL (74LS series or equivalent)

------------------------------
## 3. Frame Structure (TDM Layout)
Each Master Frame consists of exactly 8 bits transmitted sequentially at a repetition rate of 64 kHz (15.625 µs per frame).

 Master Frame Interval: 15.625 µs (8 Bits @ 512 kHz Clock)
+-----+-----+-------+-------+-------+-------+-------+-------+

|  F  |  S  |  Ch 1 |  Ch 2 |  Ch 3 |  Ch 4 |  Ch 5 |  Ch 6 |
+-----+-----+-------+-------+-------+-------+-------+-------+
 Bit:0   Bit:1   Bit:2   Bit:3   Bit:4   Bit:5   Bit:6   Bit:7

## 3.1 Bit Assignment and Mapping

* Bit 0: Framing (F) [Address 000]: Dedicated to master frame boundary alignment. This bit must alternate states every frame (1, 0, 1, 0...).
* Bit 1: Signalling (S) [Address 001]: Sub-multiplexed at 1/8th the frame rate to form a Superframe.
* Bits 2–7: Voice/Data [Address 010 to 111]: 6 channels dedicated to 64 kbps payload (e.g., CVSD voice encoders or unconstrained serial data).

------------------------------
## 4. Superframe & Signalling Structure
To accommodate call routing, ringing, and line status (A-bits) without expanding the frame size, an 8-frame Superframe structure is utilized. The S-bit (Bit 1) transitions through 8 distinct states at a sub-rate of 8 kHz (125 µs cycle time).
To simplify discrete counter implementation, Pad frames are explicitly placed at binary boundaries (Frame 3 and Frame 7).

| Frame Number | Frame Counter State (Q_F Q_E Q_D) | S-Bit Carriage | Purpose / Assignment |
|---|---|---|---|
| 0 | 000 | Channel 1 Signalling | Ring / Hook Status (A-bit) |
| 1 | 001 | Channel 2 Signalling | Ring / Hook Status (A-bit) |
| 2 | 010 | Channel 3 Signalling | Ring / Hook Status (A-bit) |
| 3 | 011 | Pad Bit (1) | Fixed Validation Guard |
| 4 | 100 | Channel 4 Signalling | Ring / Hook Status (A-bit) |
| 5 | 101 | Channel 5 Signalling | Ring / Hook Status (A-bit) |
| 6 | 110 | Channel 6 Signalling | Ring / Hook Status (A-bit) |
| 7 | 111 | Pad Bit (0) | Fixed Validation Guard |

------------------------------
## 5. Synchronization & Alignment Validation
To entirely mitigate the risk of false-locking (mimic framing) on quiet CVSD channels or repeating raw serial data, the receiving terminal must employ a Two-Stage Sync Lock State Machine:

   1. Coarse Alignment (Stage 1): The receiver monitors the assigned F-bit lane. It must detect a continuous alternating 1, 0, 1, 0 pattern across at least 8 consecutive frames to proceed.
   2. Verification Guard (Stage 2): The receiver samples Bit 1 (S-bit) when the local Frame Counter registers State 3 (011) and State 7 (111).
   * A full synchronization lock is granted only if Frame 3 == 1 and Frame 7 == 0.
      * If a signature mismatch occurs, the receiver must trigger a clock-swallow pulse to shift phase by 1 bit and reset the hunt routine.
   
