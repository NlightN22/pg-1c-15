#!/bin/bash

# Simple Patroni cluster monitoring script

echo "=== Patroni Cluster Monitor ==="
echo "Timestamp: $(date)"
echo ""

# Check etcd health
echo "1. Checking etcd health..."
if curl -s http://localhost:2379/health > /dev/null 2>&1; then
    echo "   ✓ etcd is healthy"
else
    echo "   ✗ etcd is not responding"
    exit 1
fi

echo ""

# Check Patroni REST API
echo "2. Checking Patroni REST API..."
if curl -s http://localhost:8008/patroni > /dev/null 2>&1; then
    echo "   ✓ Patroni REST API is responding"
else
    echo "   ✗ Patroni REST API is not responding"
    exit 1
fi

echo ""

# Get cluster status
echo "3. Cluster Status:"
echo "   Cluster members:"
curl -s http://localhost:8008/cluster | jq -r '.members[] | "   - \(.name): \(.role) (lag: \(.lag // "N/A"))"' 2>/dev/null || echo "   Unable to get cluster status"

echo ""

# Get node status
echo "4. Current Node Status:"
curl -s http://localhost:8008/patroni | jq -r '"   Role: \(.role)"' 2>/dev/null || echo "   Unable to get node status"
curl -s http://localhost:8008/patroni | jq -r '"   State: \(.state)"' 2>/dev/null || echo "   Unable to get node status"

echo ""

# Check PostgreSQL connection
echo "5. PostgreSQL Connection Test:"
if docker-compose exec -T pg1 pg_isready -U postgres > /dev/null 2>&1; then
    echo "   ✓ PostgreSQL is accepting connections"
else
    echo "   ✗ PostgreSQL is not accepting connections"
fi

echo ""
echo "=== End of Report ==="
