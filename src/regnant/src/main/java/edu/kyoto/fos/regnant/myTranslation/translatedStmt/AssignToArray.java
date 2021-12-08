package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;
import edu.kyoto.fos.regnant.myTranslation.TranslatedValue;
import edu.kyoto.fos.regnant.myTranslation.matchingHandler.MatchingExprHandler;
import soot.jimple.internal.JArrayRef;
import soot.jimple.internal.JAssignStmt;

public class AssignToArray implements TranslatedUnit{
  private String arrayName;
  private String index;
  private TranslatedValue value;

  public AssignToArray(JAssignStmt unit) {
    MatchingExprHandler handler = new MatchingExprHandler();

    this.arrayName = ((JArrayRef)(unit.getLeftOp())).getBase().toString();
    this.index = ((JArrayRef)(unit.getLeftOp())).getIndex().toString();
    this.value = handler.translate(unit.getRightOp());
  }

  public boolean isSequencing() {
    return true;
  }

  public String print() {
    StringBuilder builder = new StringBuilder();
    builder
      .append(arrayName)
      .append("[")
      .append(index)
      .append("] <- ")
      .append(value.print(false))
      .append(";");

    return builder.toString();
  }
}
