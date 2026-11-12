"""
iamp no terminal: o usuario digita o modelo, escolhe a distribuidora
e recebe a tarifa (R$/kWh) e quanto o aparelho gasta por mes.

Uso:
  python criar_banco.py      (uma vez, ou quando os dados mudarem)
  python app_terminal.py
"""

import sys

import banco
import servico


def brl(value, homes=2):
    """1234.5 -> 'R$ 1.234,50'"""
    text = f"{value:,.{homes}f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return f"R$ {text}"


def num(value, homes=2):
    return f"{value:,.{homes}f}".replace(",", "X").replace(".", ",").replace("X", ".")


def ask(text):
    try:
        return input(text).strip()
    except (EOFError, KeyboardInterrupt):
        print("\nAte mais!")
        sys.exit(0)


def choose(items, label):
    """Mostra uma lista numerada. Devolve o item escolhido, ou None para buscar de novo."""
    for i, item in enumerate(items, start=1):
        print(f"  {i:>2}. {label(item)}")
    while True:
        resp = ask("Numero da opcao (Enter para buscar de novo): ")
        if not resp:
            return None
        if resp.isdigit() and 1 <= int(resp) <= len(items):
            return items[int(resp) - 1]
        print("  Opcao invalida.")


def number_or_default(text, default_value):
    while True:
        resp = ask(text).replace(",", ".")
        if not resp:
            return None  # usa a estimativa do grupo
        try:
            value = float(resp)
            if value > 0:
                return value
        except ValueError:
            pass
        print("  Digite um numero maior que zero, ou Enter para usar o padrao.")


def appliance_step(con):
    print("\n1) Qual e o aparelho?")
    while True:
        text = ask("   Digite a marca e/ou o modelo (ex.: brastemp brm44): ")
        models = servico.search_models(con, text, limit=5)  # 5 por tipo: a lista fica curta
        if not models:
            print("   Nenhum modelo encontrado. Tente so a marca ou parte do modelo.")
            continue
        if len(models) == 1:
            m = models[0]
            print(f"   Encontrado: {m['marca']} {m['modelo']} ({m['categoria']})")
            return m
        choice = choose(models, lambda m: f"{m['marca']} {m['modelo']} - {m['categoria']}"
                                              + (f" ({m['detalhe']})" if m["detalhe"] else ""))
        if choice:
            return choice


def usage_step(con, appliance):
    usage = servico.usage_data(con, appliance["id"])
    hours = cycles = speed = None
    if usage["pergunta"] == "horas":
        default_value, optional = usage["padrao"], usage.get("opcional", False)
        if optional:
            tip = "Enter = usar o consumo do Inmetro"
        else:
            tip = f"Enter = {num(default_value, 1)} h, estimativa" if default_value else "obrigatorio"
        while True:
            hours = number_or_default(f"   Quantas horas por dia voce usa? [{tip}]: ", default_value)
            if hours is not None or default_value or optional:
                break
            print("   Para este aparelho preciso das horas de uso.")
    elif usage["pergunta"] == "ciclos":
        cycles = number_or_default(f"   Quantas lavagens por mes? [Enter = {num(usage['padrao'], 0)}, estimativa]: ",
                                  usage["padrao"])
    elif usage["pergunta"] == "velocidade":
        options = "/".join(usage["opcoes"])
        resp = ask(f"   Em qual velocidade voce usa ({options})? [Enter = {usage['padrao']}]: ").lower()
        speed = resp if resp in usage["opcoes"] else usage["padrao"]
    return hours, cycles, speed


def distributor_step(con):
    print("\n2) Qual e a sua distribuidora de energia? (aparece na conta de luz)")
    while True:
        resp = ask("   Digite a sigla do estado (ex.: PR), o nome (ex.: copel)\n"
                         "   ou 'conta' para digitar a tarifa da sua conta de luz: ")
        if resp.lower() == "conta":
            tariff = number_or_default("   Tarifa em R$/kWh (ex.: 0,85): ", None)
            if tariff:
                return None, tariff
            continue
        if len(resp) == 2 and resp.isalpha():
            item_list = servico.list_distributors(con, uf=resp)
        else:
            item_list = servico.list_distributors(con, search_text=resp)
        if not item_list:
            print("   Nada encontrado com tarifa cadastrada. Tente o estado ou outra parte do nome.")
            continue
        if len(item_list) == 1:
            d = item_list[0]
            print(f"   Distribuidora: {d['nome']} ({d['uf'] or 'UF nao informada'})")
            return d, None
        choice = choose(item_list, lambda d: f"{d['nome']} ({d['uf'] or '?'}) - {brl(d['tarifa_kwh'], 4)}/kWh")
        if choice:
            return choice, None


def display(r):
    print("\n" + "=" * 52)
    detail = f" ({r['detalhe']})" if r["detalhe"] else ""
    print(f" {r['marca']} {r['modelo']}{detail}")
    if r["distribuidora"] != "-":
        print(f" Distribuidora: {r['distribuidora']} - {r['uf']}")
    print("-" * 52)
    print(f" Tarifa:            {brl(r['tarifa_kwh'], 4)} por kWh")
    print(f" Consumo:           {num(r['kwh_mes'])} kWh por mes")
    print(f" Gasto por mes:     {brl(r['custo_mes'])}")
    print(f" Gasto por ano:     {brl(r['custo_ano'])}")
    print("-" * 52)
    print(f" Como calculamos: {r['metodo']}")
    print(f" Fonte da tarifa: {r['origem_tarifa']}")
    for notice in r["avisos"]:
        print(f" * {notice}")
    print("=" * 52)


def main():
    try:
        con = banco.connect()
    except ConnectionError as error:
        print(f"Erro: {error}")
        sys.exit(1)

    print("iamp - quanto o seu aparelho pesa na conta de luz")
    try:
        while True:
            appliance = appliance_step(con)
            hours, cycles, speed = usage_step(con, appliance)
            distributor, manual_tariff = distributor_step(con)
            try:
                r = servico.calculate(
                    con, appliance["id"],
                    distributor_id=distributor["id"] if distributor else None,
                    manual_tariff=manual_tariff,
                    daily_hours=hours, monthly_cycles=cycles, speed=speed,
                )
                display(r)
            except ValueError as error:
                print(f"Erro: {error}")
            if ask("\nCalcular outro aparelho? (s/n): ").lower() not in ("s", "sim"):
                print("Ate mais!")
                break
    finally:
        con.close()


if __name__ == "__main__":
    main()
