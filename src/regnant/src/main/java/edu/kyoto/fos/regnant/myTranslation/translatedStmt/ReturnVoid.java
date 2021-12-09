package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;

// 何の値も返さない return 文を表すクラス
public class ReturnVoid implements TranslatedUnit{

  public boolean isSequencing() {
    return false;
  }

  // 出力する際には0を返すようにする
  public String print() {
    return "return 0";
  }
}