import pandas as pd
import matplotlib.pyplot as plt

# Read exported CSV (replace with your file path)
df = pd.read_csv('b3_visualization.csv')  # CSV from Athena query
df.plot(kind='bar', x='Tipo', y='num_acoes', title='Número de Ações por Tipo (IBOVESPA)')
plt.xlabel('Tipo de Ação')
plt.ylabel('Número de Ações Distintas')
plt.savefig('b3_visualization.png')
plt.show()