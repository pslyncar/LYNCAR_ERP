import PostalMime from "postal-mime";

interface Env {
  API_BASE_URL: string;
  INBOUND_DOMAIN: string;
  MAX_XML_BYTES: string;
  XML_INBOUND_SECRET: string;
}

function routingToken(recipient: string, domain: string): string | null {
  const normalized = recipient.trim().toLowerCase();
  const suffix = `@${domain.toLowerCase()}`;
  if (!normalized.endsWith(suffix)) return null;

  const localPart = normalized.slice(0, -suffix.length);
  if (!localPart.startsWith("xml+")) return null;

  const separator = localPart.lastIndexOf("-");
  if (separator < 4 || separator === localPart.length - 1) return null;
  return localPart.slice(separator + 1);
}

export default {
  async email(message: ForwardableEmailMessage, env: Env): Promise<void> {
    const token = routingToken(message.to, env.INBOUND_DOMAIN);
    if (!token) {
      message.setReject("Endereco da Caixa de XML invalido.");
      return;
    }

    const parsed = await PostalMime.parse(message.raw);
    const maxBytes = Number.parseInt(env.MAX_XML_BYTES, 10) || 5_000_000;
    const xmlAttachments = parsed.attachments.filter((attachment) => {
      const filename = attachment.filename?.toLowerCase() ?? "";
      const mimeType = attachment.mimeType?.toLowerCase() ?? "";
      return filename.endsWith(".xml") || mimeType.includes("xml");
    });

    if (xmlAttachments.length === 0) {
      message.setReject("Envie ao menos um arquivo XML de NF-e anexado.");
      return;
    }

    for (const attachment of xmlAttachments) {
      const content =
        typeof attachment.content === "string"
          ? new TextEncoder().encode(attachment.content)
          : new Uint8Array(attachment.content);
      if (content.byteLength > maxBytes) {
        message.setReject("O XML anexado excede o tamanho permitido.");
        return;
      }

      const response = await fetch(
        `${env.API_BASE_URL}/xml-inbox/inbound/${encodeURIComponent(token)}`,
        {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "x-inbound-secret": env.XML_INBOUND_SECRET
          },
          body: JSON.stringify({
            sender_email: message.from,
            subject: parsed.subject ?? null,
            attachment_name: attachment.filename ?? "nota.xml",
            xml_content: new TextDecoder().decode(content)
          })
        }
      );

      if (!response.ok) {
        const body = await response.text();
        console.error("API rejected inbound XML", response.status, body);
        throw new Error(`API rejected inbound XML with status ${response.status}`);
      }
    }
  }
} satisfies ExportedHandler<Env>;
