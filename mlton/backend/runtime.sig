(* Copyright (C) 1999-2002 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-1999 NEC Research Institute.
 *
 * MLton is released under the GNU General Public License (GPL).
 * Please see the file MLton-LICENSE for license information.
 *)
type int = Int.t
type word = Word.t
   
signature RUNTIME =
   sig
      structure GCField: GC_FIELD
	 
      (* All sizes are in bytes, unless they explicitly say "pointers". *)

      val allocTooLarge: word
      val arrayHeader: {numBytesNonPointers: int,
			numPointers: int} -> word
      val arrayHeaderSize: int
      val array0Size: int
      val isValidObjectHeader: {numPointers: int,
				numWordsNonPointers: int} -> bool
      val isValidArrayHeader: {numBytesNonPointers: int,
			       numPointers: int} -> bool
      val labelSize: int
      (* Same as LIMIT_SLOP from gc.c. *)
      val limitSlop: int
      val maxFrameSize: int
      val objectHeader: {numPointers: int,
			 numWordsNonPointers: int} -> word
      val objectHeaderSize: int
      (* objectSize does not include the header. *)
      val objectSize: {numPointers: int,
		       numWordsNonPointers: int} -> int
      val pointerSize: int
      val wordAlign: word -> word (* Can raise Overflow. *)
      val wordSize: int
   end
