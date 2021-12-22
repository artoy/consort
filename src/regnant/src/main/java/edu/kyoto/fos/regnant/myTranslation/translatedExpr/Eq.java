package edu.kyoto.fos.regnant.myTranslation.translatedExpr;

import edu.kyoto.fos.regnant.myTranslation.Service.TranslateExprService;
import edu.kyoto.fos.regnant.myTranslation.TranslatedValue;
import soot.jimple.internal.JEqExpr;

public class Eq implements TranslatedValue {
	// leftOp は1つ目のオペランド, rightOp は2つ目のオペランドを表す
	private final TranslatedValue leftOp;
	private final TranslatedValue rightOp;

	public Eq(JEqExpr e) {
		TranslateExprService service = new TranslateExprService();

		this.leftOp = service.translate(e.getOp1());
		this.rightOp = service.translate(e.getOp2());
	}

	public String print(boolean isDereference) {
		StringBuilder builder = new StringBuilder();
		builder
				.append(leftOp.print(true))
				.append(" = ")
				.append(rightOp.print(true));

		return builder.toString();
	}
}
