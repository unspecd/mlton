(* Copyright (C) 1999-2002 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-1999 NEC Research Institute.
 *
 * MLton is released under the GNU General Public License (GPL).
 * Please see the file MLton-LICENSE for license information.
 *)
functor SignalCheck (S: SIGNAL_CHECK_STRUCTS): SIGNAL_CHECK = 
struct

open S
open Rssa

structure Graph = DirectedGraph
local
   open Graph
in
   structure Node = Node
   structure Edge = Edge
   structure Forest = LoopForest
end

fun insertInFunction (f: Function.t): Function.t =
   let
      val {args, blocks, name, raises, returns, start} =
	 Function.dest f
      val {get = labelIndex: Label.t -> int, set = setLabelIndex,
	   rem = remLabelIndex, ...} =
	 Property.getSetOnce
	 (Label.plist, Property.initRaise ("index", Label.layout))
      val _ =
	 Vector.foreachi (blocks, fn (i, Block.T {label, ...}) =>
			  setLabelIndex (label, i))
      val g = Graph.new ()
      val n = Vector.length blocks
      val {get = nodeIndex: unit Node.t -> int, set = setNodeIndex, ...} =
	 Property.getSetOnce
	 (Node.plist, Property.initRaise ("index", Node.layout))
      val nodes =
	 Vector.tabulate (n, fn i =>
			  let
			     val n = Graph.newNode g
			     val _ = setNodeIndex (n, i)
			  in
			     n
			  end)
      val isHeader = Array.new (n, false)
      fun indexNode i = Vector.sub (nodes, i)
      val labelNode = indexNode o labelIndex
      val _ =
	 Vector.foreachi
	 (blocks, fn (i, Block.T {label, transfer, ...}) =>
	  let
	     val from = indexNode i
	  in
	     if (case transfer of
		    Transfer.CCall {func, ...} =>
		       CFunction.maySwitchThreads func
		  | _ => false)
		then ()
	     else
		Transfer.foreachLabel
		(transfer, fn to =>
		 (Graph.addEdge (g, {from = from,
				     to = labelNode to})
		  ; ()))
	  end)
      val extra: Block.t list ref = ref []
      fun addSignalCheck (Block.T {args, kind, label, statements, transfer})
	 : unit = 
	 let
	    val failure = Label.newNoname ()
	    val success = Label.newNoname ()
	    val collect = Label.newNoname ()
	    val collectReturn = Label.newNoname ()
	    val dontCollect = Label.newNoname ()
	    val res = Var.newNoname ()
	    val compare =
	       Vector.new1
	       (Statement.PrimApp
		{args = Vector.new2 (Operand.Cast
				     (Operand.Runtime Runtime.GCField.Limit,
				      Type.defaultWord),
				     Operand.word (WordX.zero WordSize.default)),
		 dst = SOME (res, Type.bool),
		 prim = Prim.eq})
	    val compareTransfer =
	       Transfer.ifBool
	       (Operand.Var {var = res, ty = Type.bool},
		{falsee = dontCollect,
		 truee = collect})
	    val func = CFunction.gc {maySwitchThreads = true}
	    val _ =
	       extra :=
	       Block.T {args = args,
			kind = kind,
			label = label,
			statements = compare,
			transfer = compareTransfer}
	       :: (Block.T
		   {args = Vector.new0 (),
		    kind = Kind.Jump,
		    label = collect,
		    statements = Vector.new0 (),
		    transfer =
		    Transfer.CCall
		    {args = Vector.new5 (Operand.GCState,
					 Operand.word (WordX.zero
						       WordSize.default),
					 Operand.bool false,
					 Operand.File,
					 Operand.Line),
		     func = func,
		     return = SOME collectReturn}})
	       :: (Block.T
		   {args = Vector.new0 (),
		    kind = Kind.CReturn {func = func},
		    label = collectReturn,
		    statements = Vector.new0 (),
		    transfer =
		    Transfer.Goto {dst = dontCollect,
				   args = Vector.new0 ()}})
	       :: Block.T {args = Vector.new0 (),
			   kind = Kind.Jump,
			   label = dontCollect,
			   statements = statements,
			   transfer = transfer}
	       :: !extra
	 in
	    ()
	 end
      (* Create extra blocks with signal checks for all blocks that are
       * loop headers.
       *)
      fun loop (f: unit Forest.t) =
	 let
	    val {loops, ...} = Forest.dest f
	 in
	    Vector.foreach
	    (loops, fn {headers, child} =>
	     let
		val _ =
		   Vector.foreach
		   (headers, fn n =>
		    let
		       val i = nodeIndex n
		       val _ = Array.update (isHeader, i, true)
		    in
		       addSignalCheck (Vector.sub (blocks, i))
		    end)
		val _ = loop child
	     in
		()
	     end)
	 end
	    (* Add a signal check at the function entry. *)
      val newStart =
	 case Vector.peek (blocks, fn Block.T {label, ...} =>
			   Label.equals (label, start)) of
	    NONE => Error.bug "missing start block"
	  | SOME (Block.T {label, ...}) =>
	       let
		  val newStart = Label.newNoname ()
		  val _ =
		     addSignalCheck
		     (Block.T {args = Vector.new0 (),
			       kind = Kind.Jump,
			       label = newStart,
			       statements = Vector.new0 (),
			       transfer = Transfer.Goto {args = Vector.new0 (),
							 dst = start}})
	       in
		  newStart
	       end
      val forest =
	 loop
	 (Graph.loopForestSteensgaard (g, {root = labelNode start}))
      val blocks =
	 Vector.keepAllMap
	 (blocks, fn b as Block.T {label, ...} =>
	  if Array.sub (isHeader, labelIndex label)
	     then NONE
	  else SOME b)
      val blocks = Vector.concat [blocks, Vector.fromList (!extra)]
      val f = Function.new {args = args,
			    blocks = blocks,
			    name = name,
			    raises = raises,
			    returns = returns,
			    start = newStart}
      val _ = Function.clear f
   in
      f
   end

fun insert p =
   if not (Program.handlesSignals p)
      then p
   else
      let
	 val Program.T {functions, main, objectTypes} = p
      in
	 Program.T {functions = List.revMap (functions, insertInFunction),
		    main = main,
		    objectTypes = objectTypes}
      end

end
