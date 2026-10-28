# AlertaMED

Aplicativo Android, feito em Flutter, que ajuda pacientes a seguir tratamentos com medicamentos e permite que cuidadores acompanhem esse tratamento.

Foi o meu Trabalho de Conclusão de Curso em Ciência da Computação na Univali, apresentado em novembro de 2025. É um **MVP acadêmico** e não está publicado na Google Play.

<!-- Prints: adicione aqui 3 a 5 capturas de tela, por exemplo:
<p align="center">
  <img src="docs/prints/login.png" width="200">
  <img src="docs/prints/home.png" width="200">
  <img src="docs/prints/tratamento.png" width="200">
  <img src="docs/prints/assistente.png" width="200">
</p>
-->

## Funcionalidades

- **Autenticação** por e-mail e senha ou conta Google, com verificação de e-mail
- **Tratamentos:** cadastro de medicamentos, dose, horários e controle de estoque
- **Lembretes:** notificações locais nos horários do tratamento, agendadas em segundo plano com WorkManager, e modo silencioso
- **Sintomas:** registro diário e histórico
- **Cuidadores:** compartilhamento de acesso para que outra pessoa acompanhe o tratamento
- **Relatórios** em PDF e CSV para levar à consulta
- **Assistente de IA:** chat que usa o contexto do usuário (tratamentos, lembretes e sintomas recentes) para dar orientações informativas, via API da OpenAI

## Tecnologias

| Camada | Tecnologia |
| --- | --- |
| App | Flutter, Dart |
| Estado | Provider |
| Autenticação | Firebase Authentication, Google Sign-In |
| Dados | Cloud Firestore |
| Tarefas em segundo plano | WorkManager, flutter_local_notifications |
| Relatórios | pdf, share_plus |
| IA | API da OpenAI (Chat Completions) |

## Estrutura

```
lib/
├── core/            # serviços de notificação, credenciais e tarefas em segundo plano
├── providers/       # estado do usuário (Provider)
└── presentation/
    ├── pages/       # auth, onboarding, home, configuração
    ├── shared/      # widgets e modais reutilizáveis
    ├── routes/
    └── themes/
```

## Como rodar

Pré-requisitos: Flutter (SDK Dart 3.7+), um projeto Firebase e uma chave da API da OpenAI.

1. Clone o repositório e instale as dependências:
   ```bash
   flutter pub get
   ```
2. Configure o Firebase com o [FlutterFire CLI](https://firebase.google.com/docs/flutter/setup), que gera `lib/firebase_options.dart` e `android/app/google-services.json`:
   ```bash
   flutterfire configure
   ```
   Ative no console do Firebase o login por e-mail/senha e Google, e o Cloud Firestore.
3. Crie o arquivo `.env` a partir do exemplo e coloque a sua chave:
   ```bash
   cp .env.example .env
   ```
4. Rode em um emulador ou aparelho Android:
   ```bash
   flutter run
   ```

Os arquivos `.env`, `google-services.json` e `firebase_options.dart` não são versionados.

## Limitações e próximos passos

- A chamada à OpenAI é feita direto do app, então a chave vai junto no APK. Em produção, essa chamada deveria passar por um backend, como uma Cloud Function do Firebase.
- Só Android foi testado.
- O assistente é informativo e não substitui orientação médica.

## Autor

Kelvynn Bordin Calegari · [LinkedIn](https://www.linkedin.com/in/kelvynn-bordin-calegari)
