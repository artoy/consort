package edu.kyoto.fos.regnant.cfg.instrumentation;

import edu.kyoto.fos.regnant.cfg.BasicBlock;
import edu.kyoto.fos.regnant.cfg.CFGReconstructor;
import edu.kyoto.fos.regnant.cfg.graph.BlockSequence;
import edu.kyoto.fos.regnant.cfg.graph.ConditionalNode;
import edu.kyoto.fos.regnant.cfg.graph.Coord;
import edu.kyoto.fos.regnant.cfg.graph.GraphElem;
import edu.kyoto.fos.regnant.cfg.graph.InstNode;
import edu.kyoto.fos.regnant.cfg.graph.JumpNode;
import edu.kyoto.fos.regnant.cfg.graph.Jumps;
import fj.P2;

import java.util.HashSet;
import java.util.Iterator;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.function.Consumer;
import java.util.stream.Collectors;

public class FlagInstrumentation {
  public static final String GATE_ON = "gate-on";
  public static final String CHOOSE_BY = "choose-by";
  public static final String RECURSE_ON = "recurse-on";
  public static final String RETURN_ON = "return-on";
  public static final String VALUE_LOOP = "value-loop";
  public Set<Coord> setFlag = new TreeSet<>();
  public Set<Coord> returnJump = new TreeSet<>();
  public Set<Coord> recurseFlag = new TreeSet<>();

  public FlagInstrumentation(CFGReconstructor cfg) {
    recurseFlag.addAll(cfg.getRecurseLocations());
    GraphElem root = cfg.getReconstructedGraph();
    this.assignFlags(root, null);
  }

  private void assignFlags(final GraphElem graph, BasicBlock parentLoop) {
    BasicBlock childLoop = graph.isLoop() ? graph.getHead() : parentLoop;
    Consumer<GraphElem> curry = g -> assignFlags(g, childLoop);
    if(graph instanceof JumpNode) {
    } else if(graph instanceof ConditionalNode) {
      ConditionalNode cond = (ConditionalNode) graph;
      cond.fBranch.elem().ifPresent(curry);
      cond.tBranch.elem().ifPresent(curry);

      cond.tBranch.getJumps().brk.keySet().stream().map(P2::_1).forEach(returnJump::add);
      cond.fBranch.getJumps().brk.keySet().stream().map(P2::_1).forEach(returnJump::add);
    } else if(graph instanceof BlockSequence) {
      BlockSequence toCheck = (BlockSequence) graph;
      toCheck.chain.forEach(curry);

      Iterator<GraphElem> iterator = toCheck.chain.iterator();
      GraphElem hd = iterator.next();
      assert !(hd instanceof InstNode);
      Map<BasicBlock, Set<Coord>> flows = hd.getJumps().flow.stream()
          .collect(Collectors
              .groupingBy(P2::_2, Collectors
                  .mapping(P2::_1, Collectors.toSet())));
      while(iterator.hasNext()) {
        hd = iterator.next();
        boolean unconditional = hd.heads().stream().distinct().filter(flows::containsKey).count() == flows.size();
        if(!unconditional) {
          Set<Coord> gate = hd.heads().stream().flatMap(p -> flows.get(p).stream()).collect(Collectors.toSet());
          hd.putAnnotation(GATE_ON, gate);
          setFlag.addAll(gate);
        }
        if(hd instanceof InstNode) {
          InstNode inst = (InstNode) hd;
          inst.hds.stream().flatMap(c -> flows.get(c.getHead()).stream()).forEach(setFlag::add);
          Map<BasicBlock, Set<Coord>> chooseBy = inst.hds.stream().map(GraphElem::getHead).collect(Collectors.toMap(i -> i, flows::get));
          hd.putAnnotation(CHOOSE_BY, chooseBy);
        }
        hd.heads().forEach(flows::remove);
        hd.getJumps().flow.forEach(pp -> {
          flows.computeIfAbsent(pp._2(), ign -> new TreeSet<>()).add(pp._1());
        });
      }
    } else {
      assert graph instanceof InstNode;
      ((InstNode)graph).hds.forEach(curry);
    }

    Jumps jumps = graph.getJumps();
    if(parentLoop == null) {
      assert jumps.brk.isEmpty();
      assert jumps.cont.isEmpty();
    }
    if(parentLoop != null) {
      setFlag.addAll(jumps.ret);
      // if this is a loop header within a loop, AND we have continue coming out of this, then,
      // a) that continue must flag
      // b) that continue must return for its jump
      if(graph.isLoop()) {
        jumps.cont.stream().map(P2::_1).forEach(b -> {
          setFlag.add(b);
          returnJump.add(b);
          assert !recurseFlag.contains(b);
        });
      }
    }
    jumps.brk.keySet().stream().map(P2::_1).forEach(b -> {
      setFlag.add(b); returnJump.add(b);
    });

    if(graph.isLoop()) {
      Set<Coord> recurseOn = new HashSet<>();
      Set<Coord> returnOn = new HashSet<>();

      // now instrument on "return on" or "recurse on" and "value loop"
      graph.getJumps().cont.forEach(bb -> {
        assert parentLoop != null;
        if(bb._2().equals(parentLoop)) {
          recurseOn.add(bb._1());
        } else {
          returnOn.add(bb._1());
        }
      });
      graph.getJumps().brk.keySet().stream().map(P2::_1).forEach(returnOn::add);
      returnOn.addAll(graph.getJumps().ret);
      boolean valueLoop = graph.getJumps().ret.size() > 0;
      graph.putAnnotation(VALUE_LOOP, valueLoop);
      graph.putAnnotation(RETURN_ON, returnOn);
      graph.putAnnotation(RECURSE_ON, recurseOn);
    }
  }
}
