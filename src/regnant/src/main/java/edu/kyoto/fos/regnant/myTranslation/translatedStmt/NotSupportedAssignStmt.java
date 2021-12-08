package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;
import soot.Value;
import soot.jimple.AssignStmt;

public class NotSupportedAssignStmt implements TranslatedUnit{
  private AssignStmt unit;
  private Value leftOp;
  private Value rightOp;

  public NotSupportedAssignStmt(AssignStmt unit) {
    this.unit = unit;
    this.leftOp = unit.getLeftOp();
    this.rightOp = unit.getRightOp();
  }

  public boolean isSequencing() {
    return false;
  }

  public String print() {
    StringBuilder builder = new StringBuilder();
    builder
      .append("This AssignStmt is not yet supported: ")
      .append(unit.toString())
      .append(" ( Left: ")
      .append(leftOp.getClass().toString())
      .append(" Right: ")
      .append(rightOp.getClass().toString())
      .append(")");

    return builder.toString();
  }
}
