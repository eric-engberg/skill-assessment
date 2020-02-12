# ======================================================================================================================
# Imports
# ======================================================================================================================
from django.shortcuts import render
from django.views.generic import View
from .models import Product

# ======================================================================================================================
# Views
# ======================================================================================================================

class HomeView(View):
    def get(self, request):
        return render(request, 'home.html')

class ProductsView(View):
    def get(self, request):
        products = Product.objects.all()
        return render(request, 'products.html', {'products': products})
