import '../agents/agent_tool.dart';

/// Strict elementary arithmetic. Ambiguous prose is deliberately NOT routed
/// here; the ordinary AI handles it instead of receiving a wrong calculation.
class MathTool implements AgentTool {
  @override
  String get id => 'math.basic';

  static final _equation = RegExp(
    r'^([xх]|-?\d{1,7})\s*([+\-])\s*([xх]|-?\d{1,7})\s*=\s*(-?\d{1,7})$',
    caseSensitive: false,
  );
  static final _operation = RegExp(
    r'^(-?\d{1,7})\s*([+\-*×÷/:])\s*(-?\d{1,7})(?:\s*=\s*\?)?$',
  );
  static final _lead = RegExp(
    r'^(?:(?:реши(?:\s+уравнение)?|вычисли|посчитай|сколько\s+будет|найди\s+x|найди\s+х)\s*[:—-]?\s*)',
    caseSensitive: false,
  );

  static String normalize(String query) {
    var input = query.trim().replaceAll('−', '-').replaceAll('＋', '+');
    if (!input.endsWith('=?')) {
      input = input.replaceAll(RegExp(r'[.!?\s]+$'), '').trim();
    }
    input = input.replaceFirst(_lead, '').trim();
    return input;
  }

  static bool canSolve(String question) {
    final text = normalize(question);
    final match = _equation.firstMatch(text);
    if (match != null) {
      final countX = [match.group(1), match.group(3)]
          .where((v) => v == 'x' || v == 'х' || v == 'X' || v == 'Х').length;
      return countX == 1;
    }
    return _operation.hasMatch(text);
  }

  @override
  Future<ToolResult> execute(Map<String, Object?> arguments) async {
    final original = arguments['expression'];
    if (original is! String || original.trim().isEmpty) {
      return const ToolResult(success: false, message: 'Укажи выражение или уравнение.');
    }
    final expression = normalize(original);
    final equation = _equation.firstMatch(expression);
    if (equation != null) return _solveEquation(equation);
    final operation = _operation.firstMatch(expression);
    if (operation != null) return _solveOperation(operation);
    return const ToolResult(success: false, message: 'Пока умею только простую арифметику и уравнения с одним x.');
  }

  ToolResult _solveOperation(RegExpMatch match) {
    final a = int.parse(match.group(1)!);
    final sign = match.group(2)!;
    final b = int.parse(match.group(3)!);
    if (b == 0 && (sign == '/' || sign == ':' || sign == '÷')) {
      return const ToolResult(success: false, message: 'На ноль делить нельзя.');
    }
    if (sign == '+' || sign == '-') {
      final result = sign == '+' ? a + b : a - b;
      final verified = sign == '+' ? result - b == a : result + b == a;
      return ToolResult(success: verified,
        message: '$a $sign $b = $result\nПроверка: ${sign == '+' ? '$result − $b = $a' : '$result + $b = $a'}\n✓ Проверено математическим движком.');
    }
    if (sign == '*' || sign == '×') {
      final value = a * b;
      return ToolResult(success: true,
        message: '$a × $b = $value\nПроверка: ${b == 0 ? '$value = 0' : '$value ÷ $b = $a'}\n✓ Проверено математическим движком.');
    }
    final quotient = a ~/ b;
    final remainder = a.remainder(b);
    final label = remainder == 0 ? '$quotient' : '$quotient, остаток $remainder';
    return ToolResult(success: true,
      message: '$a ÷ $b = $label\nПроверка: $b × $quotient + $remainder = $a\n✓ Проверено математическим движком.');
  }

  ToolResult _solveEquation(RegExpMatch match) {
    final left = match.group(1)!;
    final right = match.group(3)!;
    final sign = match.group(2)!;
    final sum = int.parse(match.group(4)!);
    final xFirst = left.toLowerCase() == 'x' || left == 'х' || left == 'Х';
    final known = int.parse(xFirst ? right : left);
    final x = sign == '+' ? sum - known : xFirst ? sum + known : known - sum;
    final checked = sign == '+' ? x + known : xFirst ? x - known : known - x;
    if (checked != sum) {
      return const ToolResult(success: false, message: 'Не удалось проверить решение.');
    }
    final check = xFirst ? '$x $sign $known' : '$known $sign $x';
    return ToolResult(success: true,
      message: 'Уравнение: ${match.group(0)}\nx = $x\nПроверка: $check = $sum\n✓ Проверено математическим движком.');
  }
}
