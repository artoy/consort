package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;
import soot.jimple.internal.JAssignStmt;
import soot.jimple.internal.JNewArrayExpr;

public class NewArray implements TranslatedUnit{
  public String arrayName;
  public String arraySize;

  public NewArray (JAssignStmt unit) {
    this.arrayName = unit.getLeftOp().toString();
    this.arraySize = ((JNewArrayExpr)(unit.getRightOp())).getSize().toString();
  }

  public boolean isSequencing() {
    return false;
  }

  public String print() {
    StringBuilder builder = new StringBuilder();
    builder
    .append("let ")
    .append(arrayName)
    .append(" = mkarray ")
    .append(arraySize)
    .append(" in");

    return builder.toString();
  }
}
