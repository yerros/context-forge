import { Router } from "express";
import { requireUser } from "../auth";
import { db } from "../db";

export const invoices = Router();

invoices.get("/invoices", requireUser, async (req, res) => {
  const rows = await db.invoice.findMany({ where: { ownerId: req.user.id } });
  res.json(rows);
});

invoices.get("/invoices/:id/pdf", requireUser, async (req, res) => {
  const inv = await db.invoice.findUnique({ where: { id: req.params.id } });
  if (!inv) return res.status(404).end();
  res.type("application/pdf").send(await renderPdf(inv));
});
