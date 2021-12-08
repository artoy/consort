package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;
import soot.Value;
import soot.jimple.internal.JIdentityStmt;

public class Argument implements TranslatedUnit{
  private Value argumentVariable;

  public Argument(JIdentityStmt unit) {
    this.argumentVariable = unit.getLeftOp();
  }

  public boolean isSequencing() {
    return false;
  }

  public String print() {
    return "";
  }

  public String getArgumentVariable() {
    return argumentVariable.toString();
  }
}
