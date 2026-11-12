"""
Contas e casas salvas na nuvem (cadastro opcional do app).

O que guardamos e por que (LGPD):
- usuarios: nome, e-mail e a senha so como hash (scrypt com sal, da biblioteca padrao do Python; a senha
  em si nunca e gravada). O cadastro so e aceito com o aviso de privacidade aceito: a data e a versao do
  aviso ficam gravadas (consentimento registrado).
- sessoes: o app recebe um token aleatorio no login; o banco guarda so o hash dele (SHA-256), entao quem
  ler a tabela nao consegue entrar na conta. Sessao vale SESSION_DAYS dias e some no "Sair".
- casas e itens_casa: as casas da pessoa e os aparelhos de cada uma (o resultado do calculo, para o app
  montar a tela sem recalcular).
- Apagar a conta apaga tudo (ON DELETE CASCADE). O historico anonimo (tabela consultas) nao tem ligacao
  com a conta.
- Nada daqui vai para o Gemini: o Eco-Coach recebe so categorias e numeros de consumo.

Estas tabelas usam CREATE TABLE IF NOT EXISTS e nao entram no banco.SCHEMA: recarregar o catalogo
(RECARREGAR_BANCO=1) nao pode apagar as contas.
"""

import hashlib
import hmac
import json
import re
import secrets
from datetime import datetime, timedelta, timezone

import banco
from idioma import tr

PRIVACY_VERSION = "2026-11-12"
SESSION_DAYS = 30
MIN_PASSWORD = 8
MAX_PASSWORD = 128
MAX_HOMES = 10
MAX_ITEMS = 100
MAX_ITEM_DATA = 20_000  # caracteres do JSON de cada item (o resultado de um calculo tem ~2 mil)

# scrypt: parametros recomendados pelo OWASP (n=2^17 pede 128 MB; 2^14 cabe nos 512 MB do Render)
_SCRYPT = {"n": 2 ** 14, "r": 8, "p": 1, "dklen": 32}

ACCOUNT_SCHEMA = """
CREATE TABLE IF NOT EXISTS usuarios (
    id               SERIAL PRIMARY KEY,
    nome             TEXT NOT NULL,
    email            TEXT NOT NULL UNIQUE,      -- sempre em minusculas
    senha_hash       TEXT NOT NULL,             -- scrypt$n$r$p$sal$hash (nunca a senha)
    consentimento_em TIMESTAMPTZ NOT NULL,
    versao_aviso     TEXT NOT NULL,
    criado_em        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sessoes (
    token_hash TEXT PRIMARY KEY,                -- SHA-256 do token (o token so o app conhece)
    usuario_id INTEGER NOT NULL REFERENCES usuarios (id) ON DELETE CASCADE,
    criada_em  TIMESTAMPTZ NOT NULL DEFAULT now(),
    expira_em  TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessoes_usuario ON sessoes (usuario_id);

CREATE TABLE IF NOT EXISTS casas (
    id            SERIAL PRIMARY KEY,
    usuario_id    INTEGER NOT NULL REFERENCES usuarios (id) ON DELETE CASCADE,
    nome          TEXT NOT NULL,
    moradores     INTEGER NOT NULL DEFAULT 2 CHECK (moradores BETWEEN 1 AND 20),
    ultima_tarifa JSONB,                        -- tarifa que o app oferece de novo nessa casa
    criado_em     TIMESTAMPTZ NOT NULL DEFAULT now(),
    atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_casas_usuario ON casas (usuario_id);

CREATE TABLE IF NOT EXISTS itens_casa (
    id         SERIAL PRIMARY KEY,
    casa_id    INTEGER NOT NULL REFERENCES casas (id) ON DELETE CASCADE,
    posicao    INTEGER NOT NULL,
    quantidade INTEGER NOT NULL CHECK (quantidade BETWEEN 1 AND 99),
    categoria  TEXT NOT NULL,
    kwh_mes    DOUBLE PRECISION NOT NULL,       -- de 1 unidade (como o app mostra)
    custo_mes  DOUBLE PRECISION NOT NULL,
    dados      JSONB NOT NULL,                  -- pergunta + resultado do calculo, no formato do app
    UNIQUE (casa_id, posicao)
);
"""

_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class AccountError(ValueError):
    """Erro de entrada ou de regra. status = codigo HTTP que a API devolve."""

    def __init__(self, message, status=422):
        super().__init__(message)
        self.status = status


def create_tables(con):
    con.exec_driver_sql(ACCOUNT_SCHEMA)
    con.commit()


# Senha e token ------------------------------------------------------------------------------

def hash_password(password):
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, **_SCRYPT)
    return f"scrypt${_SCRYPT['n']}${_SCRYPT['r']}${_SCRYPT['p']}${salt.hex()}${digest.hex()}"


def check_password(password, stored):
    try:
        _, n, r, p, salt, digest = stored.split("$")
        expected = bytes.fromhex(digest)
        got = hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt), n=int(n), r=int(r), p=int(p),
                             dklen=len(expected))
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(got, expected)


def _token_hash(token):
    return hashlib.sha256(token.encode()).hexdigest()


def _clean_email(email):
    email = (email or "").strip().lower()
    if not _EMAIL.match(email) or len(email) > 254:
        raise AccountError(tr("e-mail invalido", "invalid e-mail"))
    return email


def _clean_name(name, field_pt="nome", field_en="name"):
    name = " ".join((name or "").split())
    if not name or len(name) > 80:
        raise AccountError(tr(f"{field_pt} deve ter de 1 a 80 letras", f"{field_en} must have 1 to 80 characters"))
    return name


def _check_new_password(password):
    if not MIN_PASSWORD <= len(password or "") <= MAX_PASSWORD:
        raise AccountError(tr(f"a senha deve ter de {MIN_PASSWORD} a {MAX_PASSWORD} caracteres",
                              f"the password must have {MIN_PASSWORD} to {MAX_PASSWORD} characters"))


def _new_session(con, user_id):
    token = secrets.token_urlsafe(32)
    expires = datetime.now(timezone.utc) + timedelta(days=SESSION_DAYS)
    banco.run(con, "INSERT INTO sessoes (token_hash, usuario_id, expira_em) VALUES (?, ?, ?)",
              (_token_hash(token), user_id, expires))
    # aproveita para limpar as sessoes vencidas dessa pessoa
    banco.run(con, "DELETE FROM sessoes WHERE usuario_id = ? AND expira_em < now()", (user_id,))
    return token


# Conta --------------------------------------------------------------------------------------

def _account(con, user_id):
    df = banco.query(con, "SELECT id, nome, email, criado_em, consentimento_em, versao_aviso "
                          "FROM usuarios WHERE id = ?", (user_id,))
    if df.empty:
        raise AccountError(tr("conta nao existe", "account does not exist"), 404)
    row = df.iloc[0]
    return {"id": int(row["id"]), "nome": row["nome"], "email": row["email"],
            "criado_em": row["criado_em"].isoformat(), "consentimento_em": row["consentimento_em"].isoformat(),
            "versao_aviso": row["versao_aviso"]}


def sign_up(con, name, email, password, accepted_privacy):
    """Cria a conta e ja abre uma sessao. Devolve (token, conta)."""
    if not accepted_privacy:
        raise AccountError(tr("e preciso aceitar o aviso de privacidade para criar a conta",
                              "you must accept the privacy notice to create an account"))
    name, email = _clean_name(name), _clean_email(email)
    _check_new_password(password)
    exists = banco.run(con, "SELECT 1 FROM usuarios WHERE email = ?", (email,)).first()
    if exists:
        raise AccountError(tr("ja existe uma conta com esse e-mail", "an account with this e-mail already exists"), 409)
    user_id = banco.run(
        con,
        "INSERT INTO usuarios (nome, email, senha_hash, consentimento_em, versao_aviso) "
        "VALUES (?, ?, ?, now(), ?) RETURNING id",
        (name, email, hash_password(password), PRIVACY_VERSION),
    ).scalar_one()
    token = _new_session(con, user_id)
    con.commit()
    return token, _account(con, user_id)


def log_in(con, email, password):
    """Devolve (token, conta). Mensagem igual para e-mail ou senha errados (nao revela quem tem conta)."""
    wrong = AccountError(tr("e-mail ou senha incorretos", "wrong e-mail or password"), 401)
    try:
        email = _clean_email(email)
    except AccountError:
        raise wrong from None
    row = banco.run(con, "SELECT id, senha_hash FROM usuarios WHERE email = ?", (email,)).first()
    if row is None:
        hash_password(password or "")  # gasta o mesmo tempo: o tempo de resposta nao revela o e-mail
        raise wrong
    if not check_password(password or "", row.senha_hash):
        raise wrong
    token = _new_session(con, row.id)
    con.commit()
    return token, _account(con, row.id)


def user_from_token(con, token):
    """Id do usuario dono do token, ou None se o token nao existe ou venceu."""
    if not token:
        return None
    row = banco.run(con, "SELECT usuario_id FROM sessoes WHERE token_hash = ? AND expira_em > now()",
                    (_token_hash(token),)).first()
    return None if row is None else row.usuario_id


def log_out(con, token):
    banco.run(con, "DELETE FROM sessoes WHERE token_hash = ?", (_token_hash(token),))
    con.commit()


def account(con, user_id):
    return _account(con, user_id)


def update_account(con, user_id, name=None, email=None):
    """Corrige nome e/ou e-mail (direito de correcao da LGPD)."""
    if name is not None:
        banco.run(con, "UPDATE usuarios SET nome = ? WHERE id = ?", (_clean_name(name), user_id))
    if email is not None:
        email = _clean_email(email)
        other = banco.run(con, "SELECT 1 FROM usuarios WHERE email = ? AND id <> ?", (email, user_id)).first()
        if other:
            raise AccountError(tr("ja existe uma conta com esse e-mail", "an account with this e-mail already exists"),
                               409)
        banco.run(con, "UPDATE usuarios SET email = ? WHERE id = ?", (email, user_id))
    con.commit()
    return _account(con, user_id)


def delete_account(con, user_id):
    """Apaga a conta, as sessoes, as casas e os itens (cascata)."""
    banco.run(con, "DELETE FROM usuarios WHERE id = ?", (user_id,))
    con.commit()


def export_data(con, user_id):
    """Tudo o que o banco guarda da pessoa (direito de acesso da LGPD), sem a senha."""
    return {"conta": _account(con, user_id), "casas": list_homes(con, user_id)}


# Casas --------------------------------------------------------------------------------------

def _json(value):
    if value is None or isinstance(value, (dict, list)):
        return value
    return json.loads(value)


def _home(con, user_id, home_id):
    df = banco.query(con, "SELECT id, nome, moradores, ultima_tarifa, atualizado_em FROM casas "
                          "WHERE id = ? AND usuario_id = ?", (home_id, user_id))
    if df.empty:
        # casa de outra pessoa responde igual a casa que nao existe
        raise AccountError(tr("casa nao existe", "home does not exist"), 404)
    row = df.iloc[0]
    items = banco.query(con, "SELECT quantidade, categoria, kwh_mes, custo_mes, dados FROM itens_casa "
                             "WHERE casa_id = ? ORDER BY posicao", (home_id,))
    return {
        "id": int(row["id"]), "nome": row["nome"], "moradores": int(row["moradores"]),
        "ultima_tarifa": _json(row["ultima_tarifa"]), "atualizado_em": row["atualizado_em"].isoformat(),
        "itens": [{"quantidade": int(i["quantidade"]), "categoria": i["categoria"], "kwh_mes": float(i["kwh_mes"]),
                   "custo_mes": float(i["custo_mes"]), "dados": _json(i["dados"])} for _, i in items.iterrows()],
    }


def list_homes(con, user_id):
    ids = banco.query(con, "SELECT id FROM casas WHERE usuario_id = ? ORDER BY id", (user_id,))["id"]
    return [_home(con, user_id, int(i)) for i in ids]


def _check_residents(residents):
    if not 1 <= int(residents) <= 20:
        raise AccountError(tr("moradores deve ser de 1 a 20", "residents must be 1 to 20"))
    return int(residents)


def create_home(con, user_id, name, residents=2):
    name = _clean_name(name, "o nome da casa", "the home name")
    total = banco.run(con, "SELECT COUNT(*) FROM casas WHERE usuario_id = ?", (user_id,)).scalar_one()
    if total >= MAX_HOMES:
        raise AccountError(tr(f"limite de {MAX_HOMES} casas por conta", f"limit of {MAX_HOMES} homes per account"))
    home_id = banco.run(con, "INSERT INTO casas (usuario_id, nome, moradores) VALUES (?, ?, ?) RETURNING id",
                        (user_id, name, _check_residents(residents))).scalar_one()
    con.commit()
    return _home(con, user_id, home_id)


def save_home(con, user_id, home_id, name, residents, last_tariff, items):
    """Grava a casa inteira (nome, moradores, ultima tarifa e a lista de itens, que substitui a anterior).
    O app manda a casa toda a cada mudanca: simples e sem conflito de itens soltos."""
    _home(con, user_id, home_id)  # 404 se nao for da pessoa
    name = _clean_name(name, "o nome da casa", "the home name")
    if len(items) > MAX_ITEMS:
        raise AccountError(tr(f"limite de {MAX_ITEMS} itens por casa", f"limit of {MAX_ITEMS} items per home"))
    rows = []
    for position, item in enumerate(items):
        data = json.dumps(item["dados"], ensure_ascii=False)
        if len(data) > MAX_ITEM_DATA:
            raise AccountError(tr("item grande demais", "item too large"))
        rows.append((home_id, position, item["quantidade"], item["categoria"], item["kwh_mes"], item["custo_mes"], data))
    banco.run(con, "UPDATE casas SET nome = ?, moradores = ?, ultima_tarifa = CAST(? AS JSONB), atualizado_em = now() "
                   "WHERE id = ?",
              (name, _check_residents(residents), None if last_tariff is None else json.dumps(last_tariff), home_id))
    banco.run(con, "DELETE FROM itens_casa WHERE casa_id = ?", (home_id,))
    for row in rows:
        banco.run(con, "INSERT INTO itens_casa (casa_id, posicao, quantidade, categoria, kwh_mes, custo_mes, dados) "
                       "VALUES (?, ?, ?, ?, ?, ?, CAST(? AS JSONB))", row)
    con.commit()
    return _home(con, user_id, home_id)


def delete_home(con, user_id, home_id):
    _home(con, user_id, home_id)
    banco.run(con, "DELETE FROM casas WHERE id = ?", (home_id,))
    con.commit()
