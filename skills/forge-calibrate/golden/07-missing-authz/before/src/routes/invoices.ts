import { Router } from "express";
import { requireUser } from "../auth";
import { db } from "../db";

export const invoices = Router();

invoices.get("/invoices", requireUser, async (req, res) => {
  const rows = await db.invoice.findMany({ where: { ownerId: req.user.id } });
  res.json(rows);
});
