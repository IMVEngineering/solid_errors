SolidErrors::Engine.routes.draw do
  get "/", to: "errors#index", as: :root

  resources :errors, only: [:index, :show, :update, :destroy], path: "" do
    resource :claim, only: [:create, :destroy]
  end
end
