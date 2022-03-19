package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;
import edu.kyoto.fos.regnant.myTranslation.TranslatedValue;
import edu.kyoto.fos.regnant.myTranslation.Service.TranslateExprService;
import soot.jimple.internal.JAssignStmt;

import java.util.HashMap;
import java.util.List;

// 変数に値を代入する式を表すクラス
public class AssignArrayToV implements TranslatedUnit {
	// variable は代入される変数の名前, value は代入する値
	private final String variable;
	private final TranslatedValue value;

	public AssignArrayToV(JAssignStmt unit) {
		TranslateExprService handler = new TranslateExprService();

		this.variable = unit.getLeftOp().toString();
		this.value = handler.translate(unit.getRightOp());
	}

	public boolean isSequencing() {
		return false;
	}

	// TODO: 健全でない．初めの基本ブロック以外で配列が新しく定義された場合エラーが起きる．
	public String print(List<String> arguments, HashMap<String, Integer> headIDs) {
		StringBuilder builder = new StringBuilder();
		builder
				.append("let ")
				.append(variable)
				.append(" = ")
				.append(value.print(false, headIDs))
				.append(" in");

		return builder.toString();
	}
}
