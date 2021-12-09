package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;
import soot.Value;
import soot.jimple.internal.JIdentityStmt;

// 基本ブロックを関数にした際に引数を設定するためのクラス
// 変換後は式としては残らない
public class Argument implements TranslatedUnit{
  // argumentVariable は引数の変数名を表す
  private final Value argumentVariable;

  public Argument(JIdentityStmt unit) {
    this.argumentVariable = unit.getLeftOp();
  }

  public boolean isSequencing() {
    return false;
  }

  public String print() {
    return "";
  }

  // 引数を外に伝えるためのメソッド
  public String getArgumentVariable() {
    return argumentVariable.toString();
  }
}
