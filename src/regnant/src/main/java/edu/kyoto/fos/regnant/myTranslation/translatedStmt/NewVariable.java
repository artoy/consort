package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;
import edu.kyoto.fos.regnant.myTranslation.TranslatedValue;
import edu.kyoto.fos.regnant.myTranslation.Service.TranslateExprService;
import soot.jimple.internal.JAssignStmt;

// 変数を (ポインタで) 定義する式を表すクラス
public class NewVariable implements TranslatedUnit{
  // variable は定義する変数の名前, value は変数を初期化する値
  private String variable;
  private TranslatedValue value;

  public NewVariable(JAssignStmt unit){
    TranslateExprService service = new TranslateExprService();

    this.variable = unit.getLeftOp().toString();
    this.value = service.translate(unit.getRightOp());
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