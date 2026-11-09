# windows-setup-auto

Instala seus apps (via `winget`) e otimiza o Windows 10/11.

## Uso
1. Copie esta pasta para o Windows.
2. Edite `apps.json` (`"enabled": true/false`) para escolher os apps.
3. Dê duplo clique em `run.bat` (ele pede Administrador).
   - Ou: `run.bat -All`, `run.bat -Install`, `run.bat -Optimize`, `run.bat -Debloat`.
   - `-All -Debloat` faz tudo, incluindo a remoção de bloatware.

## Privacidade reforçada (opcional)
`run.bat -Privacy` ou opção 7 do menu. Não roda com `-All` e pede confirmação.
Vai além da privacidade básica da otimização: desativa ID de anúncio, telemetria extra,
relatórios de erro, tarefas CEIP, histórico de atividades, sincronização de área de
transferência, localização, Recall, Copilot, pesquisa web no Iniciar, Wi-Fi Sense e
P2P de atualizações. Pode afetar: Localizar meu dispositivo, mapas/clima por localização
e histórico da área de transferência (Win+V). Desfaça pelo ponto de restauração.

## Drivers (opcional)
`run.bat -Drivers` ou opção 6 do menu. Não roda com `-All`.
1. Detecta CPU, GPU e fabricante.
2. Lista e instala os drivers pendentes do Windows Update (módulo PSWindowsUpdate), com confirmação.
3. Instala a ferramenta oficial conforme o hardware: NVIDIA App, Intel Driver & Support
   Assistant, Dell Command Update ou Lenovo System Update. Para AMD, mostra o link de download.

## Remoção de bloatware (opcional)
Nunca roda sozinha com `-All`: só com `-Debloat` ou pela opção 3/5 do menu.
A lista está em `bloatware.json` (aceita curingas `*`, e `enabled` liga/desliga cada item).
O script mostra o que será removido e pede confirmação. Ao final, também remove o
**OneDrive** (confirmação separada, com aviso sobre arquivos só na nuvem; sua pasta local
não é apagada). Para pular, coloque `"removeOneDrive": false` no `bloatware.json`. Loja, Calculadora, Fotos e
Bloco de Notas ficam de fora. Phone Link, To Do, Outlook, Spotify e Xbox vêm desativados
na lista; ative se quiser removê-los. Tudo pode ser reinstalado pela Microsoft Store.

## O que otimiza
- Cria ponto de restauração antes de tudo
- Plano de energia Alto desempenho
- Telemetria mínima, sem anúncios/sugestões/busca Bing no Iniciar
- Desativa Game DVR e serviços inúteis (DiagTrack etc.)
- Explorer: extensões e ocultos visíveis, long paths
- Efeitos visuais reduzidos, hibernação off, limpeza de temp, TRIM

Tudo é registrado em `setup-*.log`. Para desfazer, use o ponto de restauração.

## Adicionar um app
`winget search <nome>` e adicione o ID em `apps.json`.
