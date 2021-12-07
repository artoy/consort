package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;

public class AssertFail implements TranslatedUnit{
  public boolean isSequencing() {
    return true;
  }
  
  public String print() {
    return("fail;");
  }
}
