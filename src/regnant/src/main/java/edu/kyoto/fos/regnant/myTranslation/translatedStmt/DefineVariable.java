package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;
import edu.kyoto.fos.regnant.myTranslation.TranslatedValue;
import edu.kyoto.fos.regnant.myTranslation.matchingHandler.MatchingExprHandler;
import soot.jimple.internal.JAssignStmt;

public class DefineVariable implements TranslatedUnit{
  private String variable;
  private TranslatedValue value;

  public DefineVariable(JAssignStmt unit){
    MatchingExprHandler handler = new MatchingExprHandler();

    this.variable = unit.getLeftOp().toString();
    this.value = handler.translate(unit.getRightOp());
  }

  public boolean isSequencing() {
    return false;
  }

  public String print() {
    StringBuilder builder = new StringBuilder();
    builder
      .append("let ")
      .append(variable)
      .append(" = mkref ")
      .append(value.print(false))
      .append(" in");

    return builder.toString();
  }
}