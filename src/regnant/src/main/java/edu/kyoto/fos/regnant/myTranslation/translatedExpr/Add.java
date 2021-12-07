package edu.kyoto.fos.regnant.myTranslation.translatedExpr;

public class Add {
  private translatedExpr leftOp;
  private translatedExpr rightOp;

  public Add() {
    
  }

  private string print() {
    StringBuilder builder = new StringBuilder();
    builder
      .append(leftOp.print())
      .append(" + ")
      .append(rightOp.print());

    return builder.toString();
  }
}
