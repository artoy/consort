package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;
import soot.Unit;

public class NotSupportedUnit implements TranslatedUnit{
  public Unit unit;
  
  public NotSupportedUnit(Unit unit) {
    this.unit = unit;
  }

  public boolean isSequencing() {
    return false;
  }

  public String print() {
    StringBuilder builder = new StringBuilder();
    builder
        .append("This unit is not yet supported: ")
        .append(unit.toString())
        .append(" (")
        .append(unit.getClass().toString())
        .append(")");

    return builder.toString();
  }
}
