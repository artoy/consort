package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;

public class If implements TranslatedUnit {
  private String condition;
  private String thenUnit;
  private String elseUnit;
  
  public boolean isSequencing() {
    return false;
  }

  public String print() {
    return "not supported yet.";
  }
}
