import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import syncProducts from '@salesforce/apex/ProductService.syncProducts';
import getProducts from '@salesforce/apex/ProductService.getProducts';
import deleteAllProducts from '@salesforce/apex/ProductService.deleteAllProducts';
import needsSync from '@salesforce/apex/ProductService.needsSync';
import { applyFilters, sortProducts, applyBusinessRules } from './productUtils';

// Business rules for product limits and pricing
const BUSINESS_RULES = {
    MAX_PRODUCTS: 100,
    MAX_TOTAL_PRICE: 10000
};

export default class ProductVisualizer extends LightningElement {
    // Track product data and UI state
    @track products = [];
    @track carouselIndexes = {};
    
    // Filter state
    @track filters = {
        searchTerm: '',
        selectedCategories: [],
        selectedBrands: []
    };
    
    // Sorting state
    sortBy = 'name';
    sortDirection = 'asc';
    
    // Loading and error states
    isLoading = false;
    error;
    needsInitialSync = false;
    syncStarted = false;
    
    // UI state
    expandedRowId = null;
    wiredProductsResult;
    wiredNeedsSyncResult;

    // Get brand options for dropdown
    get brandOptions() {
        return this.getUniqueOptions('Brand');
    }

    // Get category options for dropdown
    get categoryOptions() {
        return this.getUniqueOptions('Family');
    }

    // Calculate total stock across all filtered products
    get totalStock() {
        return this.filteredProducts.reduce((sum, product) => sum + (product.Stock || 0), 0);
    }

    // Wire up product data from Apex
    @wire(getProducts)
    wiredProducts(result) {
        this._wiredProductsResult = result;
        const { error, data } = result;
        if (data) {
            const uniqueProducts = Array.isArray(data) ? data : [];
            this.products = uniqueProducts.filter((product, index, self) =>
                index === self.findIndex((p) => p.Id === product.Id)
            );
            this.error = undefined;
            if (this.products.length === 0) {
                this.checkAutoSync();
            }
        } else if (error) {
            this.handleError('Error loading products', error);
            this.products = [];
        }
    }

    // Check if products need to be synced
    @wire(needsSync)
    wiredNeedsSync(result) {
        this.wiredNeedsSyncResult = result;
        const { error, data } = result;
        if (data && !this.syncStarted) {
            this.needsInitialSync = data;
            if (data) {
                this.showToast('Info', 'No products found. Starting automatic sync...', 'info');
                this.handleSync();
            }
        } else if (error) {
            this.handleError('Error checking sync status', error);
        }
    }

    // Get filtered and sorted products
    get filteredProducts() {
        if (!this.products?.length) return [];
        
        // First, group products by category
        const productsByCategory = this.products.reduce((acc, product) => {
            const category = product.Family;
            if (!acc[category]) {
                acc[category] = [];
            }
            acc[category].push(product);
            return acc;
        }, {});

        // Apply business rules to each category
        const filteredByCategory = Object.entries(productsByCategory).reduce((acc, [category, products]) => {
            // Apply business rules to this category's products
            const filteredProducts = applyBusinessRules(products, {
                ...BUSINESS_RULES,
                selectedCategory: category
            });
            return [...acc, ...filteredProducts];
        }, []);

        // Now apply the user's filters and sorting
        const enrichedProducts = filteredByCategory.map(this.enrichProductData.bind(this));
        const filtered = enrichedProducts
            .filter(product => applyFilters(product, this.filters))
            .sort((a, b) => sortProducts(a, b, this.sortBy, this.sortDirection));
        
        return filtered;
    }

    // Handle search input changes
    handleSearchChange(event) {
        this.filters.searchTerm = event.target.value;
    }

    // Handle category filter changes
    handleCategoryChange(event) {
        this.filters.selectedCategories = event.detail.map(item => item.value);
    }

    // Handle brand filter changes
    handleBrandChange(event) {
        this.filters.selectedBrands = event.detail.map(item => item.value);
    }

    // Handle row click to expand/collapse
    handleRowClick(event) {
        const productId = event.currentTarget.dataset.id;
        this.toggleRowExpansion(productId);
    }

    // Navigate to next image in carousel
    handleNextImage(event) {
        const productId = event.currentTarget.dataset.id;
        this.updateCarouselIndex(productId, 1);
    }

    // Navigate to previous image in carousel
    handlePrevImage(event) {
        const productId = event.currentTarget.dataset.id;
        this.updateCarouselIndex(productId, -1);
    }

    // Sync products from external source
    async handleSync() {
        try {
            this.isLoading = true;
            this.syncStarted = true;
            const result = await syncProducts();
            this.showToast('Success', result, 'success');
            this.resetFilters();
            await this.refreshAllData();
        } catch (error) {
            this.handleError('Error syncing products', error);
        } finally {
            this.isLoading = false;
        }
    }

    // Delete all products
    async handleDeleteAll() {
        try {
            this.isLoading = true;
            await deleteAllProducts();
            this.showToast('Success', 'All products deleted successfully', 'success');
            this.resetData();
            await this.refreshAllData();
        } catch (error) {
            this.handleError('Error deleting products', error);
        } finally {
            this.isLoading = false;
        }
    }

    // Show toast notification
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    // Handle and display errors
    handleError(message, error) {
        this.error = error;
        const errorMessage = error.body?.message || error.message || message;
        this.showToast('Error', errorMessage, 'error');
    }

    // Get available sort options
    get sortOptions() {
        return [
            { label: 'Name (A-Z)', value: 'name_asc' },
            { label: 'Name (Z-A)', value: 'name_desc' },
            { label: 'Price (Low to High)', value: 'price_asc' },
            { label: 'Price (High to Low)', value: 'price_desc' },
            { label: 'Stock (Low to High)', value: 'stock_asc' },
            { label: 'Stock (High to Low)', value: 'stock_desc' }
        ];
    }

    // Get current sort value
    get sortByValue() {
        return `${this.sortBy}_${this.sortDirection}`;
    }

    // Handle sort option changes
    handleSortChange(event) {
        const [field, direction] = event.target.value.split('_');
        this.sortBy = field;
        this.sortDirection = direction;
    }

    // Add computed properties to product data
    enrichProductData(product) {
        const images = product.Images?.split(',') || [];
        return {
            ...product,
            Brand: product.Brand || 'Unknown Brand',
            isExpanded: this.expandedRowId === product.Id,
            expandedKey: product.Id + '-expanded',
            hasImages: images.length > 0,
            hasMultipleImages: images.length > 1,
            imageCount: images.length,
            currentImage: images[this.carouselIndexes[product.Id] || 0] || product.DisplayUrl,
            imageIndex: (this.carouselIndexes[product.Id] || 0) + 1,
            tagsArray: product.Tags?.split(',').map(tag => tag.trim()) || []
        };
    }

    // Get unique options for dropdown filters
    getUniqueOptions(field) {
        this.filters.selectedCategories = this.filters.selectedCategories || [];
        this.filters.selectedBrands = this.filters.selectedBrands || [];
        
        const selectedValues = field === 'Family' ? this.filters.selectedCategories : this.filters.selectedBrands;
        
        if (!this.products?.length) {
            return [];
        }
        
        return Array.from(new Set(this.products.map(product => product[field]).filter(Boolean)))
            .sort((a, b) => a.localeCompare(b))
            .map(value => ({
                label: value,
                value: value,
                key: `${field.toLowerCase()}_${value}`,
                selected: selectedValues.includes(value)
            }));
    }

    // Toggle product row expansion
    toggleRowExpansion(productId) {
        const wasExpanded = this.expandedRowId === productId;
        this.expandedRowId = wasExpanded ? null : productId;
        if (this.expandedRowId === null) {
            this.carouselIndexes = {};
        }
    }

    // Update carousel image index
    updateCarouselIndex(productId, direction) {
        const product = this.products.find(p => p.Id === productId);
        if (!product) return;

        const images = product.Images?.split(',').map(url => url.trim()) || [];
        if (images.length <= 1) return;

        const currentIndex = this.carouselIndexes[productId] || 0;
        const newIndex = (currentIndex + direction + images.length) % images.length;
        
        this.carouselIndexes = { 
            ...this.carouselIndexes, 
            [productId]: newIndex 
        };
    }

    // Check if we need to auto-sync products
    checkAutoSync() {
        if (this.products.length === 0 && !this.syncStarted && !this.filters.searchTerm && !this.filters.selectedCategories.length && !this.filters.selectedBrands.length) {
            this.handleSync();
        }
    }

    // Reset all filters to default state
    resetFilters() {
        this.filters = {
            searchTerm: '',
            selectedCategories: [],
            selectedBrands: []
        };
    }

    // Reset all component data
    resetData() {
        this.products = [];
        this.expandedRowId = null;
        this.resetFilters();
        this.syncStarted = false;
    }

    // Refresh all wire data
    async refreshAllData() {
        await Promise.all([
            refreshApex(this._wiredProductsResult),
            refreshApex(this.wiredNeedsSyncResult)
        ]);
    }

    // Check if we should show no products message
    get showNoProductsMessage() {
        return this.products.length === 0 && !this.filters.searchTerm && !this.filters.selectedCategories.length && !this.filters.selectedBrands.length;
    }

    // Check if any filters are active
    get isFilterActive() {
        return !!(this.filters.searchTerm || this.filters.selectedCategories.length || this.filters.selectedBrands.length);
    }

    // Check if we should show sync message
    get showSyncMessage() {
        return this.products.length === 0 && !this.isFilterActive;
    }

    // Check if we should show no filtered products message
    get showNoFilteredProductsMessage() {
        return this.products.length > 0 && this.filteredProducts.length === 0;
    }
}