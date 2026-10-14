# BitWorker
This projects is a custom networking implement that works on top of the Roblox game engine.
Though Roblox does a lot itself, this project squeezes as much performance as possible out of what Roblox exposes.

List of optimizations:
  1. One single buffer per packet (excluding instance references)
  2. Type-Length-Value (TLV) encoding
  3. Variable length integers
  4. Packet caching
  5. Better outgoing packet control
  6. Better incoming packet handling
  7. Bit-masks for sparse packets
  8. Sub-byte encoding for values that don't need a full byte representation
  9. Bit-packing (ties back into 7)
  10. Repetitive packets (packets that repeat their data over and over, saving on type encoding data)
  11. Packet "specialization." Allowing packets to be predefined into larger sets of data to avoid over-generalizing data structures (which costs in packet size).


I've also done my best to make it as easy as possible to use with strict type enforcement, it should be pretty hard to break!
