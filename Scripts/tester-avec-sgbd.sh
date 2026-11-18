#!/bin/zsh
# Lance tous les tests de Cardinal, y compris l'exécution réelle des scripts dans PostgreSQL et MariaDB.
# Les deux serveurs sont démarrés dans un dossier temporaire puis arrêtés : rien n'est installé
# comme service. Prérequis : brew install postgresql@17 mariadb
set -e
cd "$(dirname "$0")/.."
D=$(mktemp -d /tmp/cardinal-sgbd.XXXXXX)
PG=$(brew --prefix postgresql@17)/bin
MB=$(brew --prefix mariadb)/bin
export LC_ALL=C

$PG/initdb -D $D/pg -U cardinal --auth=trust -E UTF8 --locale=C >/dev/null
$PG/pg_ctl -D $D/pg -o "-p 54329 -k $D -c listen_addresses=''" -l $D/pg.log start >/dev/null
$MB/mariadb-install-db --datadir=$D/maria --auth-root-authentication-method=socket --skip-test-db >/dev/null 2>&1
$MB/mariadbd --datadir=$D/maria --socket=$D/maria.sock --skip-networking --pid-file=$D/maria.pid --log-error=$D/maria.err &
arreter() {
  # Toujours arrêter les serveurs d'abord ; chaque étape est tolérante (rien ne doit l'interrompre).
  $PG/pg_ctl -D $D/pg stop -m fast >/dev/null 2>&1 || true
  kill $(cat $D/maria.pid 2>/dev/null) 2>/dev/null || true
  # La copie de test de l'app ne doit pas apparaître dans la liste des applications.
  for app in build.noindex/Build/Products/*/Cardinal.app(N); do
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$app" 2>/dev/null || true
  done
  sleep 1; rm -rf $D
}
trap arreter EXIT
sleep 4

# Affiche le bilan ; si la compilation échoue (aucun bilan), montre la fin du journal.
bilan() {
  grep -E "^(✔|✘) Test run|failed after|\.swift:[0-9]+:[0-9]+: error:" $1 || { echo "Échec avant les tests :"; tail -30 $1; return 1; }
  ! grep -q "^✘ Test run" $1
}
# Le projet Xcode est régénéré : un nouveau fichier de test ne peut pas être oublié.
xcodegen generate >/dev/null
echo "== Application macOS (interface + moteur) =="
TEST_RUNNER_CARDINAL_DB_DIR=$D xcodebuild -project Cardinal.xcodeproj -scheme Cardinal -derivedDataPath build.noindex test > $D/app.log 2>&1 || true
bilan $D/app.log
echo "== Moteur seul, comme sous Windows et Linux (sans police macOS) =="
(cd Core && CARDINAL_DB_DIR=$D swift test -Xswiftc -DCARDINAL_PORTABLE > $D/core.log 2>&1) || true
bilan $D/core.log
