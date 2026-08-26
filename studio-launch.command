#!/bin/bash
# Двойной клик → поднимает локальный сервер в папке slides/ и открывает BStudio.
# Камера в браузере работает только через http://localhost (не file://), поэтому так.
#
# Чем поднимать сервер. На чистом маке без Xcode Command Line Tools `python3` —
# это заглушка: при запуске она тянет установку CLT (несколько гигабайт и
# диалог), а сервера не поднимает. Поэтому python3 берём только настоящий —
# из Homebrew или когда CLT уже стоят, — а иначе идём в perl и ruby: они в
# macOS есть из коробки и Xcode не требуют.
# Принудительно: BSTUDIO_SERVER=python|perl|ruby ./studio-launch.command

cd "$(dirname "$0")" || exit 1
PAGE="studio.html"
[ -f "$PAGE" ] || { echo "Рядом нет $PAGE — положи этот файл в папку студии."; exit 1; }

# --- свободный порт: /dev/tcp умеет сам bash, ничего внешнего не нужно -------
PORT=""
p=8000
while [ "$p" -le 8020 ]; do
  if (echo >/dev/tcp/127.0.0.1/$p) 2>/dev/null; then
    p=$((p+1))                      # занят, берём следующий
  else
    PORT=$p; break
  fi
done
[ -n "$PORT" ] || { echo "Свободного порта 8000-8020 не нашлось. Помогает перезагрузка."; exit 1; }

# --- чем поднимать ----------------------------------------------------------
SRV="$BSTUDIO_SERVER"
PY=""
if [ -z "$SRV" ]; then
  for c in /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    [ -x "$c" ] && { PY="$c"; break; }
  done
  if [ -z "$PY" ] && xcode-select -p >/dev/null 2>&1 && [ -x /usr/bin/python3 ]; then PY=/usr/bin/python3; fi
  if   [ -n "$PY" ];                  then SRV=python
  elif command -v perl >/dev/null 2>&1; then SRV=perl
  elif command -v ruby >/dev/null 2>&1; then SRV=ruby
  else
    echo "Не нашёл, чем поднять локальный сервер: нет ни настоящего python3, ни perl, ни ruby."
    echo "Поставь любой из них — или Homebrew-python3 (brew install python), или Xcode Command Line Tools."
    exit 1
  fi
fi
[ "$SRV" = python ] && [ -z "$PY" ] && PY="$(command -v python3)"

URL="http://localhost:${PORT}/${PAGE}"
( sleep 1
  if command -v open >/dev/null 2>&1; then open "$URL"; else echo "Открой в браузере: $URL"; fi
) &

echo "BStudio открыта: $URL   (сервер: $SRV)"
echo "Это окно держит сервер. Закончишь — Ctrl+C или закрой окно."

case "$SRV" in
  python) exec "$PY" -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 ;;
  ruby)   exec ruby -run -e httpd -- -p "$PORT" -b 127.0.0.1 . >/dev/null 2>&1 ;;
esac

# --- perl: сервер статики на голых core-модулях --------------------------------
exec perl - "$PORT" <<'PERL'
use strict; use warnings;
use IO::Socket::INET;
my $port = shift || 8000;
my %T = (
  html=>'text/html; charset=utf-8', htm=>'text/html; charset=utf-8',
  js=>'text/javascript; charset=utf-8', mjs=>'text/javascript; charset=utf-8',
  css=>'text/css; charset=utf-8', json=>'application/json; charset=utf-8',
  md=>'text/markdown; charset=utf-8', txt=>'text/plain; charset=utf-8',
  png=>'image/png', jpg=>'image/jpeg', jpeg=>'image/jpeg', gif=>'image/gif',
  svg=>'image/svg+xml', webp=>'image/webp', avif=>'image/avif', bmp=>'image/bmp',
  ico=>'image/x-icon', pdf=>'application/pdf', webm=>'video/webm', mp4=>'video/mp4',
  woff=>'font/woff', woff2=>'font/woff2',
);
my $srv = IO::Socket::INET->new(LocalAddr=>'127.0.0.1', LocalPort=>$port,
  Listen=>32, ReuseAddr=>1, Proto=>'tcp') or die "порт $port занять не удалось: $!\n";
$SIG{PIPE} = 'IGNORE';
while (my $c = $srv->accept) {
  my $line = <$c>;
  unless (defined $line) { close $c; next; }
  while (my $h = <$c>) { last if $h =~ /^\s*$/; }          # дочитываем заголовки
  my ($method, $uri) = $line =~ m{^(\w+)\s+(\S+)};
  $uri = '/' unless defined $uri;
  $uri =~ s/\?.*//;                                         # query не нужен
  $uri =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;              # %XX в имени файла
  $uri = '/studio.html' if $uri eq '/';
  $uri =~ s{^/+}{};
  my $bad = ($uri =~ m{(^|/)\.\.(/|$)});                    # выше папки не пускаем
  my ($code, $body, $ctype) = (404, 'not found', 'text/plain; charset=utf-8');
  if (!$bad && -f $uri && open(my $fh, '<', $uri)) {
    binmode $fh; local $/; $body = <$fh>; close $fh;
    my ($ext) = $uri =~ /\.([A-Za-z0-9]+)$/;
    $ctype = $T{lc(defined $ext ? $ext : '')} || 'application/octet-stream';
    $code = 200;
  }
  print $c "HTTP/1.1 $code " . ($code == 200 ? 'OK' : 'Not Found') . "\r\n"
         . "Content-Type: $ctype\r\nContent-Length: " . length($body) . "\r\n"
         . "Cache-Control: no-store\r\nConnection: close\r\n\r\n";
  print $c $body unless (defined $method && $method eq 'HEAD');
  close $c;
}
PERL
