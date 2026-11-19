# Registro de uso de IA — RotaAlerta / Operating Systems

A IA foi utilizada como copiloto para estruturar e revisar uma extensão de infraestrutura Linux e uma demonstração Web complementar ao projeto mobile RotaAlerta. O código deve ser compreendido, validado e explicado pelos integrantes da equipe.

## Prompts utilizados (resumo)

1. Atuar como engenheiro DevOps e especialista Linux/Ubuntu para elaborar os entregáveis de Operating Systems da Global Solution FIAP, seguindo os slides 35, 36 e 37.
2. Inspecionar o repositório RotaAlerta existente e identificar como hospedar uma experiência Web sem quebrar o aplicativo React Native/Expo.
3. Criar um frontend e backend Node.js leves para demonstrar rota habitual e cenários simulados de alagamento, acidente e Zona Azul.
4. Criar scripts Bash separados para provisionar hostname/rede/DNS/IP, instalar dependências e publicar a aplicação, além de monitorar CPU, RAM e disco com alertas.
5. Criar unidades systemd com reinício automático, trilha de auditoria, documentação de instalação, testes de falha e roteiro para vídeo de até sete minutos.

## Validações que a equipe deve executar

- Conferir os valores de interface, IP e gateway antes de usar modo estático.
- Executar `bash -n os/scripts/*.sh` e revisar os logs.
- Executar os scripts na VM Ubuntu limpa do grupo.
- Testar API, Nginx, serviços systemd, alertas e recuperação após falha.
- Saber explicar a função de cada arquivo e as limitações dos dados simulados.
