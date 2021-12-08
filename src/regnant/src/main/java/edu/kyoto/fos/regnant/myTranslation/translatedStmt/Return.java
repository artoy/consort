package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;
import soot.Value;
import soot.jimple.internal.JReturnStmt;

public class Return implements TranslatedUnit {
  private Value returnValue;

  public Return(JReturnStmt unit) {
    this.returnValue = unit.getOp();
  }

  public boolean isSequencing() {
    return false;
  }

  public String print() {
    StringBuilder builder = new StringBuilder();
    builder
      .append("return ")
      .append(returnValue.toString());

    return builder.toString();
  }
}