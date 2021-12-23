package edu.kyoto.fos.regnant.myTranslation.translatedExpr;

import edu.kyoto.fos.regnant.myTranslation.TranslatedValue;
import soot.jimple.internal.JimpleLocal;

// 変換された JimpleLocal を表す
public class Variable implements TranslatedValue {
	// variable は JimpleLocal そのものを表す
	private final JimpleLocal variable;

	public Variable(JimpleLocal variable) {
		this.variable = variable;
	}

	public String print(boolean isDereference) {
		StringBuilder builder = new StringBuilder();
		if (isDereference) builder.append("*");
		builder.append(variable.toString());

		return builder.toString();
	}
}
