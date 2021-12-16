package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.cfg.BasicBlock;
import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;
import soot.jimple.internal.JGotoStmt;

import java.util.List;

public class Goto implements TranslatedUnit {
  private BasicBlock target;

  public Goto(JGotoStmt unit, List<BasicBlock> nextBasicBlocks) {
    assert(nextBasicBlocks.size() == 1);
    this.target = nextBasicBlocks.get(0);
  }

  public boolean isSequencing() {
    return false;
  }

  public String print() {
    return toFunctionCall(target);
  }
}
