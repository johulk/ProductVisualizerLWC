// Filter products based on search term, categories, and brands
export function applyFilters(product, filters) {
    const { searchTerm, selectedCategories, selectedBrands } = filters;
    
    // Check search term
    if (searchTerm) {
        const searchLower = searchTerm.toLowerCase();
        const matchesSearch = 
            product.Name?.toLowerCase().includes(searchLower) ||
            product.Description?.toLowerCase().includes(searchLower) ||
            product.Brand?.toLowerCase().includes(searchLower) ||
            product.Family?.toLowerCase().includes(searchLower);
        
        if (!matchesSearch) return false;
    }
    
    // Check categories
    if (selectedCategories?.length > 0) {
        if (!selectedCategories.includes(product.Family)) return false;
    }
    
    // Check brands
    if (selectedBrands?.length > 0) {
        if (!selectedBrands.includes(product.Brand)) return false;
    }
    
    return true;
}

// Sort products by field and direction
export function sortProducts(a, b, sortBy, sortDirection) {
    let valueA, valueB;
    
    // Get values based on sort field
    switch (sortBy) {
        case 'name':
            valueA = a.Name?.toLowerCase() || '';
            valueB = b.Name?.toLowerCase() || '';
            break;
        case 'price':
            valueA = a.UnitPrice || 0;
            valueB = b.UnitPrice || 0;
            break;
        case 'stock':
            valueA = a.Stock || 0;
            valueB = b.Stock || 0;
            break;
        default:
            valueA = a[sortBy] || '';
            valueB = b[sortBy] || '';
    }
    
    // Compare values
    if (valueA < valueB) return sortDirection === 'asc' ? -1 : 1;
    if (valueA > valueB) return sortDirection === 'asc' ? 1 : -1;
    return 0;
}

// Apply business rules to product list
export function applyBusinessRules(products, rules) {
    const { MAX_PRODUCTS, MAX_TOTAL_PRICE } = rules;
    
    // Sort products by price (highest to lowest) to maximize value within limits
    const sortedProducts = [...products].sort((a, b) => (b.UnitPrice || 0) - (a.UnitPrice || 0));
    
    let totalPrice = 0;
    let count = 0;
    
    // Filter products based on both limits
    return sortedProducts.filter(product => {
        const price = product.UnitPrice || 0;
        
        // Check if adding this product would exceed either limit
        if (count >= MAX_PRODUCTS || totalPrice + price > MAX_TOTAL_PRICE) {
            return false;
        }
        
        // Add product to the filtered list
        totalPrice += price;
        count++;
        return true;
    });
}

// Business rules utility
export function applyCategoryBusinessRules(products, { MAX_PRODUCTS, MAX_TOTAL_PRICE }) {
    return products
        .sort((a, b) => (b.UnitPrice || 0) - (a.UnitPrice || 0))
        .reduce((acc, prod) => {
            const currentSum = acc.reduce((sum, p) => sum + (p.UnitPrice || 0), 0);
            if (acc.length < MAX_PRODUCTS && currentSum + (prod.UnitPrice || 0) <= MAX_TOTAL_PRICE) {
                acc.push(prod);
            }
            return acc;
        }, []);
}

export function applyGlobalBusinessRules(products, { MAX_PRODUCTS, MAX_TOTAL_PRICE }) {
    const categoryMap = products.reduce((map, product) => {
        const cat = product.Family;
        if (!map.has(cat)) map.set(cat, []);
        map.get(cat).push(product);
        return map;
    }, new Map());
    return Array.from(categoryMap.values()).flatMap(prods =>
        applyCategoryBusinessRules(prods, { MAX_PRODUCTS, MAX_TOTAL_PRICE })
    );
}