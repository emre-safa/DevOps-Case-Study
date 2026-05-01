import React, { useEffect, useState } from "react";

const API_BASE = process.env.REACT_APP_API_URL || "";

export default function HealthStatus() {
  const [status, setStatus] = useState([]);

  useEffect(() => {
    fetch(`${API_BASE}/healthcheck/`)
      .then((response) => response.json())
      .then((data) => setStatus(data));
  }, []);

  return (
    <div>
      <h3>API Status</h3>
      {JSON.stringify(status)}
    </div>
  );
}
