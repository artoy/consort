package edu.kyoto.fos.regnant.myTranslation.matchingHandler;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;
import edu.kyoto.fos.regnant.myTranslation.translatedStmt.Argument;
import edu.kyoto.fos.regnant.myTranslation.translatedStmt.AssertFail;
import edu.kyoto.fos.regnant.myTranslation.translatedStmt.AssignToArray;
import edu.kyoto.fos.regnant.myTranslation.translatedStmt.AssignToVariable;
import edu.kyoto.fos.regnant.myTranslation.translatedStmt.NewVariable;
import edu.kyoto.fos.regnant.myTranslation.translatedStmt.NewArray;
import edu.kyoto.fos.regnant.myTranslation.translatedStmt.NotSupportedAssignStmt;
import edu.kyoto.fos.regnant.myTranslation.translatedStmt.NotSupportedUnit;
import edu.kyoto.fos.regnant.myTranslation.translatedStmt.Return;
import edu.kyoto.fos.regnant.myTranslation.translatedStmt.ReturnVoid;
import soot.Unit;
import soot.jimple.internal.JArrayRef;
import soot.jimple.internal.JAssignStmt;
import soot.jimple.internal.JIdentityStmt;
import soot.jimple.internal.JNewArrayExpr;
import soot.jimple.internal.JNopStmt;
import soot.jimple.internal.JReturnStmt;
import soot.jimple.internal.JReturnVoidStmt;
import soot.jimple.internal.JimpleLocal;

public class MatchingStmtHandler {
  
  public TranslatedUnit translate(Unit unit, boolean headOfFunction) {
    // Java SE 12 以降も使えるようにしたら switch 文に書き換える
    if (unit instanceof JNopStmt) {
      // nop の場合 (assert が失敗した場合)
      return new AssertFail();
    } else if (unit instanceof JReturnVoidStmt) {
      // 何も返さない return 文の場合
      return new ReturnVoid();
    } else if (unit instanceof JReturnStmt) {
      // 値を返す return 文の場合
      return new Return((JReturnStmt)unit);
    } else if (unit instanceof JIdentityStmt) {
      // メソッドの引数は IdentityStmt で定義されるからその情報を argument に入れる
      return new Argument((JIdentityStmt)unit);
    } else if (unit instanceof JAssignStmt) {
      // 代入文の場合
      JAssignStmt assignUnit = (JAssignStmt)unit;

      if (assignUnit.getRightOp() instanceof JNewArrayExpr) {
        // 配列を新しく作る場合
        return new NewArray(assignUnit);
      } else if (assignUnit.getLeftOp() instanceof JArrayRef) {
        // 配列の要素を更新する場合 (もし初期化の場合のみ <- を使うとかだったら要修正)
        return new AssignToArray(assignUnit);
      } else if (assignUnit.getLeftOp() instanceof JimpleLocal && headOfFunction) {
        // 初めて変数が定義される場合 (関数の中の最初の基本ブロックに変数定義が全て含まれているという仮説による)
        return new NewVariable(assignUnit);
      } else if (assignUnit.getLeftOp() instanceof JimpleLocal) {
        // 定義されている変数に値を代入する場合
        return new AssignToVariable(assignUnit);
      // TODO: InvokeStmt にも対応する
      } else {
        // throw new RuntimeException("This AssignStmt is not yet supported: " + unit + " ( Left: " + assignUnit.getLeftOp().getClass().toString() + " Right: " + assignUnit.getRightOp().getClass().toString() + ")");
        // デバッグのための, エラーの代わりの標準出力
        return new NotSupportedAssignStmt(assignUnit);
      }
    } else {
      // throw new RuntimeException("This unit is not yet supported: " + unit + " (" + unit.getClass() + ")");
      // デバッグのための, エラーのための標準出力
      return new NotSupportedUnit(unit);
    }
  }
}
