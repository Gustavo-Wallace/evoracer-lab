# EVO RACER LAB

Simulação de corrida 2D vista de cima criada no Godot 4.7. O projeto combina física arcade retrô, pistas reutilizáveis, sensores, telemetria competitiva e uma primeira rede neural feedforward. A base seguirá evoluindo para múltiplas pistas e treinamento evolutivo de agentes.

## Executar

Abra a pasta no Godot 4.7 e execute a cena principal com **F6/F5**.

- **W/S/A/D**: dirigir o carro manual.
- **1/2/3/4**: câmera selecionada, líder, aleatória ou visão geral.
- **Q/E**, **G**, **M**: trocar alvo, sortear alvo e voltar ao manual.
- **V**: sensores e telemetria neural do carro acompanhado.
- **K**: gerar novos pesos e reposicionar os agentes neurais.
- **F**: iniciar ou reiniciar uma avaliação com 12 agentes neurais.
- **B**: encerrar o modo de avaliação e voltar ao teste manual.
- **H**: ocultar ou exibir os resultados da avaliação.
- **L**, **P**, **R**, **N**: classificação, checkpoints, respawn manual e nova corrida.

O projeto já calcula fitness e resultados de avaliações neurais. Ainda não há seleção genética, elitismo, cruzamento, mutação ou gerações automáticas.
