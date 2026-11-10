# SD as Internal Storage on Android Devices

[English](README.md) | **Português (Brasil)**

Ferramenta gráfica para Windows que usa o ADB para listar o cartão de memória de um aparelho Android, formatá-lo como **armazenamento interno** (armazenamento adotável) ou voltá-lo ao **modo portátil**.

Muitos fabricantes e operadoras escondem a opção "Formatar como interno" do menu do cartão, mesmo quando o Android suporta o recurso. A ferramenta usa os comandos do próprio sistema (`sm`), que continuam disponíveis.

> **Atenção:** as duas opções de formatação apagam todo o conteúdo do cartão.

## Recursos

- Encontra o `adb.exe` no PATH ou no Android SDK.
- Lista os aparelhos conectados e avisa quando falta autorizar o PC.
- Mostra cada cartão com tamanho, modo atual (Portátil, Armazenamento interno ou Misto), volumes e espaço usado.
- Mostra a versão do Android e se o aparelho aceita armazenamento adotável. Desativa os botões que não se aplicam.
- Pede confirmação antes de formatar e registra cada comando e a resposta.
- Tela inicial de dicas: como ativar o modo de desenvolvedor e a Depuração USB, versões do Android suportadas e problemas comuns.
- Interface no idioma do Windows: português do Brasil em sistemas em português e inglês internacional nos demais. Para forçar um idioma, use `-Lang pt` ou `-Lang en`.

## Requisitos

- Windows 10 ou 11 (Windows PowerShell 5.1, já incluído).
- [Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools) (`adb`).
- Aparelho com Android 6.0 ou mais novo, com a Depuração USB ativada.

## Versões do Android

| Versão | Cartão como armazenamento interno |
|---|---|
| 5.1 ou anterior | Não suportado |
| 6.0 a 8.1 | Suportado; costuma aparecer no menu do cartão |
| 9 a 15 | Suportado pelo sistema; muitos fabricantes escondem a opção do menu |
| Mais novas que 15 | Não verificado |

Alguns fabricantes (por exemplo, aparelhos Samsung Galaxy recentes) bloqueiam o recurso. Nesse caso a ferramenta mostra "Suporte a armazenamento interno: não" e só permite o modo portátil.

Testado em: TCL TAB 10 5G (9183W, firmware T-Mobile), Android 12.

## Como usar

1. No aparelho, ative as **Opções do desenvolvedor** (toque 7 vezes em *Configurações > Sobre o telefone > Número da versão*) e a **Depuração USB**.
2. Conecte o cabo, desbloqueie a tela e aceite o aviso **"Permitir depuração USB?"**.
3. No PC, abra **`Cartao SD ADB.bat`** (ou rode o comando abaixo).
4. Clique em **Listar cartões**, selecione o cartão e escolha a ação.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File sd_adb_tool.ps1
```

Depois de formatar como interno, mova os apps em *Configurações > Apps > [app] > Armazenamento > Alterar*. Antes de remover o cartão ou voltar ao modo portátil, traga os apps de volta para a memória interna.

## Comandos usados

| Ação | Comando |
|---|---|
| Listar cartões | `adb shell dumpsys mount` |
| Verificar suporte | `adb shell sm has-adoptable` |
| Formatar como interno | `adb shell sm partition <disco> private` |
| Voltar ao modo portátil | `adb shell sm partition <disco> public` |

## Licença

[MIT](LICENSE)
