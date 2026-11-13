import pickle
from datetime import date
from functools import lru_cache
from pathlib import Path

from idioma import t, tr

MODEL = Path(__file__).resolve().parents[1] / "models" / "refrigerador.pkl"

ORDINANCE_SOURCE_2006 = "Portaria Inmetro 20/2006, RESP/001-REF, Anexo VI"
TABLE_SOURCE_2001 = "Tabela Inmetro 2001 via Queiroz et al., ACEEE Summer Study 2003"
FI_SOURCE = "Fatores de desgaste por idade: Jannuzzi/Unicamp e estudo de campo da Unifei (premissa do grupo)"

LINES_2006 = {
    "Refrigerador": (0.0346, 19.117),
    "Combinado": (0.0916, 17.083),
    "Combinado frost free": (0.1059, 7.4862),
    "Congelador vertical": (0.0211, 39.228),
    "Congelador vertical frost free": (0.0178, 58.712),
    "Congelador horizontal": (0.0758, 13.095),
}
CLASS_A_LIMIT_2006 = {"Combinado frost free": 0.846}
DEFAULT_CLASS_A_LIMIT_2006 = 0.855
STARS_FACTOR_2006 = {1: 1.41, 2: 1.63, 3: 1.85}
FROST_FREE_FACTOR_2006 = 1.2

RULE_YEAR_2006 = 2006
NEW_LABEL_YEAR = 2023
MIN_YEAR = 1980
MAX_VOLUME_L = 1000
FI_RANGES = ((5, 1.00), (10, 1.10), (float("inf"), 1.30))

TYPES = {
    "1_porta": {"nome": "geladeira 1 porta", "tipo_inmetro": "Refrigerador", "estrelas": 1, "so_congelador": False},
    "frigobar": {"nome": "frigobar", "tipo_inmetro": "Frigobar", "estrelas": 1, "so_congelador": False},
    "duplex": {"nome": "geladeira duplex", "tipo_inmetro": "Refrigerador-Congelador", "estrelas": 3, "so_congelador": False},
    "freezer_vertical": {"nome": "freezer vertical", "tipo_inmetro": "Congelador Vertical", "estrelas": 3, "so_congelador": True},
    "freezer_horizontal": {"nome": "freezer horizontal", "tipo_inmetro": "Congelador Horizontal", "estrelas": 3, "so_congelador": True},
}

APPROXIMATE_NOTICE = ("Gasto aproximado: o modelo não está no catálogo do Inmetro, então o consumo foi estimado "
                    "pelo tipo, volume e ano de compra. O valor real pode estar em qualquer ponto da faixa.")
LABEL_NOTICE = ("Consumo da etiqueta do aparelho, convertido para a metodologia de ensaio atual e ajustado "
                  "pelo desgaste da idade.")
TYPICAL_POWER_NOTICE = ("A potência usada é a típica da categoria (estimativa do grupo). Informe a da etiqueta "
                         "do aparelho para um valor mais preciso.")


@lru_cache(maxsize=1)
def load_model(path=MODEL):
    if not Path(path).exists():
        raise FileNotFoundError(f"{path} nao existe. Rode: python scripts/treinar_refrigerador.py")
    with open(path, "rb") as f:
        return pickle.load(f)


def category_2006(inmetro_type, frost_free):
    if inmetro_type in ("Refrigerador", "Frigobar"):
        return "Refrigerador"
    if inmetro_type == "Refrigerador-Congelador":
        return "Combinado frost free" if frost_free else "Combinado"
    if inmetro_type == "Congelador Vertical":
        return "Congelador vertical frost free" if frost_free else "Congelador vertical"
    return "Congelador horizontal"


def adjusted_volume_2006(refrigerator_volume, freezer_by_stars, frost_free):
    freezer = sum(STARS_FACTOR_2006[stars] * volume for stars, volume in freezer_by_stars.items())
    return (refrigerator_volume + freezer) * (FROST_FREE_FACTOR_2006 if frost_free else 1.0)


def default_consumption_2006(category, adjusted_volume):
    a, b = LINES_2006[category]
    return a * adjusted_volume + b


def time_per_day(hours):
    total = round(hours * 60)
    h, m = divmod(total, 60)
    text = f"{m} min" if h == 0 else (f"{h} h" if m == 0 else f"{h} h {m} min")
    return text + tr("/dia", "/day")


def age_factor(age):
    if age < 0:
        raise ValueError(tr("o ano de compra não pode ser no futuro", "the year of purchase cannot be in the future"))
    return next(factor for limit, factor in FI_RANGES if age <= limit)


def _validate(kind, volume_total_l, freezer_volume_l, purchase_year, reference_year):
    if kind not in TYPES:
        raise ValueError(tr(f"tipo precisa ser um de: {', '.join(TYPES)}", f"type must be one of: {', '.join(TYPES)}"))
    if not 0 < volume_total_l <= MAX_VOLUME_L:
        raise ValueError(tr(f"o volume total precisa estar entre 1 e {MAX_VOLUME_L} litros",
                            f"the total volume must be between 1 and {MAX_VOLUME_L} liters"))
    if freezer_volume_l is not None and not 0 <= freezer_volume_l <= volume_total_l:
        raise ValueError(tr("o volume do freezer precisa estar entre 0 e o volume total",
                            "the freezer volume must be between 0 and the total volume"))
    if not MIN_YEAR <= purchase_year <= reference_year:
        raise ValueError(tr(f"o ano de compra precisa estar entre {MIN_YEAR} e {reference_year}",
                            f"the year of purchase must be between {MIN_YEAR} and {reference_year}"))


def _segment(model, grid, inmetro_type, frost_free):
    return model[grid][(inmetro_type, frost_free)]


def _prediction(segment, model, volume):
    start, end = model["volumes"]
    index = int(round(min(max(volume, start), end))) - start
    return segment["kwh_mes"][index]


def _conversion(model, inmetro_type, frost_free):
    return model["fator_metodo"].get((inmetro_type, frost_free), model["fator_metodo_geral"])


def methodology_factor(inmetro_type, frost_free, model=None):
    return _conversion(model or load_model(), inmetro_type, bool(frost_free))["mediana"]


def _mae_2025(model, inmetro_type, frost_free):
    for line in model["metricas"]["2025"]["por_segmento"]:
        if line["tipo"] == inmetro_type and bool(line["frost_free"]) == frost_free:
            return float(line["mae_rf"])
    return float(model["metricas"]["2025"]["mae"])


def _by_label(model, info, frost_free, kwh_label, purchase_year, fi):
    if purchase_year >= NEW_LABEL_YEAR:
        base = kwh_label
        return {"kwh_mes": base * fi, "kwh_min": base * fi, "kwh_max": base * fi,
                "metodo": tr(f"etiqueta {kwh_label:g} kWh/mês (metodologia atual) x Fi {fi:.2f}",
                             f"label {kwh_label:g} kWh/month (current method) x Fi {fi:.2f} (age wear)")}
    conversion = _conversion(model, info["tipo_inmetro"], frost_free)
    return {
        "kwh_mes": kwh_label * conversion["mediana"] * fi,
        "kwh_min": kwh_label * conversion["p25"] * fi,
        "kwh_max": kwh_label * conversion["p75"] * fi,
        "metodo": tr(f"etiqueta {kwh_label:g} kWh/mês (metodologia antiga) x {conversion['mediana']:.2f} "
                     f"(conversão para a metodologia atual) x Fi {fi:.2f}",
                     f"label {kwh_label:g} kWh/month (old method) x {conversion['mediana']:.2f} "
                     f"(conversion to the current method) x Fi {fi:.2f} (age wear)"),
    }


def _by_rule_2006(model, info, frost_free, volume_total_l, freezer_volume_l, purchase_year, fi):
    inmetro_type = info["tipo_inmetro"]
    if info["so_congelador"]:
        refrigerator, freezer = 0.0, volume_total_l
    else:
        if freezer_volume_l is None:
            freezer_volume_l = volume_total_l * model["fracao_congelador"].get(
                (inmetro_type, frost_free), model["fracao_congelador_geral"])
        refrigerator, freezer = volume_total_l - freezer_volume_l, freezer_volume_l
    category = category_2006(inmetro_type, frost_free)
    av = adjusted_volume_2006(refrigerator, {info["estrelas"]: freezer}, frost_free)
    cp = default_consumption_2006(category, av)

    if purchase_year < RULE_YEAR_2006:
        ie = model["ie_2001"]
        ie_min, ie_point, ie_max = ie["p25"], ie["media"], ie["p75"]
        era = tr("tabela Inmetro 2001", "Inmetro 2001 table")
    else:
        ie_min = model["ie_regra_2006"].get(category, model["ie_regra_2006_geral"])["mediana"]
        ie_max = CLASS_A_LIMIT_2006.get(category, DEFAULT_CLASS_A_LIMIT_2006)
        ie_point, era = (ie_min + ie_max) / 2, tr("regra de 2006 (classe A)", "2006 rule (class A)")
    conversion = _conversion(model, inmetro_type, frost_free)["mediana"]
    return {
        "kwh_mes": ie_point * cp * conversion * fi,
        "kwh_min": ie_min * cp * conversion * fi,
        "kwh_max": ie_max * cp * conversion * fi,
        "metodo": tr(f"consumo padrão {cp:.1f} kWh/mês ({category}, volume ajustado {av:.0f} L) x índice "
                     f"{ie_point:.2f} ({era}, faixa {ie_min:.2f} a {ie_max:.2f}) x {conversion:.2f} "
                     f"(conversão para a metodologia atual) x Fi {fi:.2f}",
                     f"standard consumption {cp:.1f} kWh/month ({t(category)}, adjusted volume {av:.0f} L) x index "
                     f"{ie_point:.2f} ({era}, range {ie_min:.2f} to {ie_max:.2f}) x {conversion:.2f} "
                     f"(conversion to the current method) x Fi {fi:.2f} (age wear)"),
    }


def _by_current_model(model, info, frost_free, volume_total_l, fi):
    segment = _segment(model, "grade_2025", info["tipo_inmetro"], frost_free)
    predicted = _prediction(segment, model, volume_total_l)
    error = _mae_2025(model, info["tipo_inmetro"], frost_free)
    return {
        "kwh_mes": predicted * fi,
        "kwh_min": max(predicted - error, 0.0) * fi,
        "kwh_max": (predicted + error) * fi,
        "metodo": tr(f"Random Forest com os modelos atuais do Inmetro: {predicted:.1f} kWh/mês "
                     f"(erro médio {error:.1f}) x Fi {fi:.2f}",
                     f"Random Forest with Inmetro's current models: {predicted:.1f} kWh/month "
                     f"(mean error {error:.1f}) x Fi {fi:.2f} (age wear)"),
    }


def estimated_refrigerator_consumption(kind, frost_free, volume_total_l, purchase_year, freezer_volume_l=None,
                                  kwh_label=None, reference_year=None, model=None):
    reference_year = reference_year or date.today().year
    _validate(kind, volume_total_l, freezer_volume_l, purchase_year, reference_year)
    if kwh_label is not None and kwh_label <= 0:
        raise ValueError(tr("o consumo da etiqueta precisa ser maior que zero", "the label consumption must be greater than zero"))
    model = model or load_model()
    info = TYPES[kind]
    age = reference_year - purchase_year
    fi = age_factor(age)

    if kwh_label is not None:
        calculation, notices, sources = _by_label(model, info, frost_free, kwh_label, purchase_year, fi), [t(LABEL_NOTICE)], [FI_SOURCE]
    elif purchase_year >= NEW_LABEL_YEAR:
        calculation, notices, sources = _by_current_model(model, info, frost_free, volume_total_l, fi), [t(APPROXIMATE_NOTICE)], [model["fonte"], FI_SOURCE]
    else:
        calculation = _by_rule_2006(model, info, frost_free, volume_total_l, freezer_volume_l, purchase_year, fi)
        notices, sources = [t(APPROXIMATE_NOTICE)], [ORDINANCE_SOURCE_2006, TABLE_SOURCE_2001, FI_SOURCE]

    if age > model["vida_util_anos"]:
        notices.append(tr(f"Com {age} anos, o aparelho passou da vida útil média de {model['vida_util_anos']} anos.",
                         f"At {age} years old, the appliance is past the average lifespan of "
                         f"{model['vida_util_anos']} years."))
    name = t(info["nome"])
    description = tr(f"{name}{' frost-free' if frost_free else ''}, {volume_total_l:g} L, comprada em {purchase_year}",
                   f"{name}{' frost-free' if frost_free else ''}, {volume_total_l:g} L, bought in {purchase_year}")
    return {
        **calculation,
        "categoria": "refrigerador",
        "nome": name.capitalize(),
        "tipo": info["tipo_inmetro"],
        "capacidade": float(volume_total_l),
        "detalhe": description,
        "idade_anos": age,
        "fator_idade": fi,
        "premissa": False,
        "aproximado": True,
        "avisos": notices,
        "fonte": "; ".join(sources),
    }


def resistive_consumption(default_value, power_w=None, daily_hours=None, days_per_month=None):
    category = default_value["categoria"]
    power = default_value["potencia_w"] if power_w is None else power_w
    hours = default_value["horas_dia"] if daily_hours is None else daily_hours
    days = default_value["dias_mes"] if days_per_month is None else days_per_month
    if power <= 0:
        raise ValueError(tr("a potência precisa ser maior que zero", "the power must be greater than zero"))
    if not 0 <= hours <= 24:
        raise ValueError(tr("horas por dia precisa estar entre 0 e 24", "hours per day must be between 0 and 24"))
    if not 1 <= days <= 31:  # 0 dias nao e uso (igual ao ar-condicionado)
        raise ValueError(tr("os dias de uso no mês precisam estar entre 1 e 31", "days of use per month must be between 1 and 31"))

    return {
        "kwh_mes": power / 1000 * hours * days,
        "metodo": (f"{power:g} W ({_origin(power_w)}) / 1000 x {time_per_day(hours)} ({_origin(daily_hours)}) "
                   f"x {days:g} {tr('dias', 'days')} ({_origin(days_per_month)})"),
        "categoria": category,
        "nome": default_value["nome"],
        "detalhe": f"{default_value['nome']}, {power:g} W",
        "horas_dia": hours,
        "dias_mes": days,
        "premissa": daily_hours is None or days_per_month is None,
        "aproximado": None in (power_w, daily_hours, days_per_month),
        "avisos": [] if power_w is not None else [t(TYPICAL_POWER_NOTICE)],
        "fonte": "potencia x tempo de uso" + ("" if power_w is not None else f"; potencia tipica: {default_value['fonte']}"),
    }


def _origin(given):
    return tr("informado", "entered") if given is not None else tr("padrão do grupo", "group default")
