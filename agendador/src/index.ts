/// <reference types="@cloudflare/workers-types" />
// Cada cron dispara um workflow do repositório via API do GitHub.
const REPO = "paulobarros/res_pedra";

const WORKFLOWS: Record<string, string> = {
  "7 * * * *": "update_data.yml",
  "0 10 * * *": "telegram_relatorio.yml",
};

interface Env {
  GITHUB_TOKEN: string;
}

async function disparar(workflow: string, env: Env): Promise<void> {
  // remove espaços/quebras de linha que podem vir ao colar o token
  const token = (env.GITHUB_TOKEN ?? "").trim();
  if (!token) throw new Error("secret GITHUB_TOKEN vazio");
  const resp = await fetch(
    `https://api.github.com/repos/${REPO}/actions/workflows/${workflow}/dispatches`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "res-pedra-agendador",
      },
      body: JSON.stringify({ ref: "main" }),
    },
  );
  // 204 = disparado
  if (resp.status !== 204) {
    // diagnóstico sem expor o token: só prefixo e tamanho
    const formato = `${token.startsWith("github_pat_") ? "formato github_pat_ ok" : "NÃO parece um token do GitHub"}, ${token.length} caracteres`;
    throw new Error(`${workflow}: GitHub respondeu ${resp.status} | token ${formato} | ${(await resp.text()).slice(0, 120)}`);
  }
  console.log(`${workflow}: disparado`);
}

export default {
  async scheduled(controller, env, ctx) {
    const workflow = WORKFLOWS[controller.cron];
    if (!workflow) {
      console.warn(`cron sem workflow associado: ${controller.cron}`);
      return;
    }
    ctx.waitUntil(disparar(workflow, env));
  },
} satisfies ExportedHandler<Env>;
