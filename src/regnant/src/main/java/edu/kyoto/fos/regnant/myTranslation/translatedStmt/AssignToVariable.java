package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;
import edu.kyoto.fos.regnant.myTranslation.TranslatedValue;
import edu.kyoto.fos.regnant.myTranslation.matchingHandler.MatchingExprHandler;
import soot.jimple.internal.JAssignStmt;

// 変数に値を代入する式を表すクラス
public class AssignToVariable implements TranslatedUnit{
  // variable は代入される変数の名前, value は代入する値
  private String variable;
  private TranslatedValue value;

  public AssignToVariable(JAssignStmt unit){
    MatchingExprHandler handler = new MatchingExprHandler();

    this.variable = unit.getLeftOp().toString();
    this.value = handler.translate(unit.getRightOp());
  }

  public boolean isSequencing() {
    return true;
  }

  public String print() {
    StringBuilder builder = new StringBuilder();
    builder
      .append(variable)
      .append(" := ")
      .append(value.print(false))
      .append(";");

    return builder.toString();
  }
}
