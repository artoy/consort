package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;

// assert 文が失敗する場合に到達する式を表すクラス
public class AssertFail implements TranslatedUnit{
  public boolean isSequencing() {
    return true;
  }
  
  public String print() {
    return("fail;");
  }
}
