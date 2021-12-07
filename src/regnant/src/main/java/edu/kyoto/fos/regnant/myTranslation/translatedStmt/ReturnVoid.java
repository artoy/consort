package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;

public class ReturnVoid implements TranslatedUnit{

  public boolean isSequencing() {
    return false;
  }

  public String print() {
    return "return 0";
  }
}