## Información de prueba
* **POST http://34.238.23.161:8080/api/v1/ventas**
{
  "direccionCompra": "Av. Providencia 1234, Santiago",
  "valorCompra": 250000,
  "fechaCompra": "2025-05-17",
  "despachoGenerado": false
}

* **POST http://34.238.23.161:8081/api/v1/despachos**
{
  "fechaDespacho": "2025-05-20",
  "patenteCamion": "GHIJ34",
  "intento": 0,
  "idCompra": 2,
  "direccionCompra": "Av. Providencia 1234, Santiago",
  "valorCompra": 250000,
  "despachado": false
}
