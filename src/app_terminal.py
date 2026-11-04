"""
WattWise no terminal: o usuario digita o modelo, escolhe a distribuidora
e recebe a tarifa (R$/kWh) e quanto o aparelho gasta por mes.

Uso:
  python criar_banco.py      (uma vez, ou quando os dados mudarem)
  python app_terminal.py
"""

import sys

import banco
import servico


def brl(valor, casas=2):
    """1234.5 -> 'R$ 1.234,50'"""
    texto = f"{valor:,.{casas}f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return f"R$ {texto}"


def num(valor, casas=2):
    return f"{valor:,.{casas}f}".replace(",", "X").replace(".", ",").replace("X", ".")


def perguntar(texto):
    try:
        return input(texto).strip()
    except (EOFError, KeyboardInterrupt):
        print("\nAte mais!")
        sys.exit(0)


def escolher(itens, rotulo):
    """Mostra uma lista numerada. Devolve o item escolhido, ou None para buscar de novo."""
    for i, item in enumerate(itens, start=1):
        print(f"  {i:>2}. {rotulo(item)}")
    while True:
        resp = perguntar("Numero da opcao (Enter para buscar de novo): ")
        if not resp:
            return None
        if resp.isdigit() and 1 <= int(resp) <= len(itens):
            return itens[int(resp) - 1]
        print("  Opcao invalida.")


def numero_ou_padrao(texto, padrao):
    while True:
        resp = perguntar(texto).replace(",", ".")
        if not resp:
            return None  # usa a estimativa do grupo
        try:
            valor = float(resp)
            if valor > 0:
                return valor
        except ValueError:
            pass
        print("  Digite um numero maior que zero, ou Enter para usar o padrao.")


def passo_aparelho(con):
    print("\n1) Qual e o aparelho?")
    while True:
        texto = perguntar("   Digite a marca e/ou o modelo (ex.: brastemp brm44): ")
        modelos = servico.buscar_modelos(con, texto)
        if not modelos:
            print("   Nenhum modelo encontrado. Tente so a marca ou parte do modelo.")
            continue
        if len(modelos) == 1:
            m = modelos[0]
            print(f"   Encontrado: {m['marca']} {m['modelo']} ({m['categoria']})")
            return m
        escolha = escolher(modelos, lambda m: f"{m['marca']} {m['modelo']} - {m['categoria']}"
                                              + (f" ({m['detalhe']})" if m["detalhe"] else ""))
        if escolha:
            return escolha


def passo_uso(con, aparelho):
    uso = servico.dados_de_uso(con, aparelho["id"])
    horas = ciclos = velocidade = None
    if uso["pergunta"] == "horas":
        padrao = uso["padrao"]
        dica = f"Enter = {num(padrao, 1)} h, estimativa" if padrao else "obrigatorio"
        while True:
            horas = numero_ou_padrao(f"   Quantas horas por dia voce usa? [{dica}]: ", padrao)
            if horas is not None or padrao:
                break
            print("   Para este aparelho preciso das horas de uso.")
    elif uso["pergunta"] == "ciclos":
        ciclos = numero_ou_padrao(f"   Quantas lavagens por mes? [Enter = {num(uso['padrao'], 0)}, estimativa]: ",
                                  uso["padrao"])
    elif uso["pergunta"] == "velocidade":
        opcoes = "/".join(uso["opcoes"])
        resp = perguntar(f"   Em qual velocidade voce usa ({opcoes})? [Enter = {uso['padrao']}]: ").lower()
        velocidade = resp if resp in uso["opcoes"] else uso["padrao"]
    return horas, ciclos, velocidade


def passo_distribuidora(con):
    print("\n2) Qual e a sua distribuidora de energia? (aparece na conta de luz)")
    while True:
        resp = perguntar("   Digite a sigla do estado (ex.: PR), o nome (ex.: copel)\n"
                         "   ou 'conta' para digitar a tarifa da sua conta de luz: ")
        if resp.lower() == "conta":
            tarifa = numero_ou_padrao("   Tarifa em R$/kWh (ex.: 0,85): ", None)
            if tarifa:
                return None, tarifa
            continue
        if len(resp) == 2 and resp.isalpha():
            lista = servico.listar_distribuidoras(con, uf=resp)
        else:
            lista = servico.listar_distribuidoras(con, busca=resp)
        if not lista:
            print("   Nada encontrado com tarifa cadastrada. Tente o estado ou outra parte do nome.")
            continue
        if len(lista) == 1:
            d = lista[0]
            print(f"   Distribuidora: {d['nome']} ({d['uf'] or 'UF nao informada'})")
            return d, None
        escolha = escolher(lista, lambda d: f"{d['nome']} ({d['uf'] or '?'}) - {brl(d['tarifa_kwh'], 4)}/kWh")
        if escolha:
            return escolha, None


def mostrar(r):
    print("\n" + "=" * 52)
    detalhe = f" ({r['detalhe']})" if r["detalhe"] else ""
    print(f" {r['marca']} {r['modelo']}{detalhe}")
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
    for aviso in r["avisos"]:
        print(f" * {aviso}")
    print("=" * 52)


def main():
    try:
        con = banco.conectar()
    except ConnectionError as erro:
        print(f"Erro: {erro}")
        sys.exit(1)

    print("WattWise - quanto o seu aparelho pesa na conta de luz")
    try:
        while True:
            aparelho = passo_aparelho(con)
            horas, ciclos, velocidade = passo_uso(con, aparelho)
            distribuidora, tarifa_manual = passo_distribuidora(con)
            try:
                r = servico.calcular(
                    con, aparelho["id"],
                    distribuidora_id=distribuidora["id"] if distribuidora else None,
                    tarifa_manual=tarifa_manual,
                    horas_dia=horas, ciclos_mes=ciclos, velocidade=velocidade,
                )
                mostrar(r)
            except ValueError as erro:
                print(f"Erro: {erro}")
            if perguntar("\nCalcular outro aparelho? (s/n): ").lower() not in ("s", "sim"):
                print("Ate mais!")
                break
    finally:
        con.close()


if __name__ == "__main__":
    main()
